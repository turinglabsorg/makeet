package push

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/go-jose/go-jose/v4"
	"github.com/google/uuid"
)

var ErrUnavailable = errors.New("push provider unavailable")

type Config struct {
	TeamID, KeyID, Environment string
	PrivateKey, EncryptionKey  []byte
	Topics                     []string
	HTTPClient                 *http.Client
	Endpoint                   string
	Clock                      func() time.Time
}

type Client struct {
	environment string
	topics      map[string]bool
	teamID      string
	signer      jose.Signer
	cipher      cipher.AEAD
	http        *http.Client
	endpoint    string
	clock       func() time.Time
	mu          sync.Mutex
	assertion   string
	issued      time.Time
}

type Result struct {
	Accepted, InvalidToken, Retryable bool
}

func New(cfg Config) (*Client, error) {
	block, rest := pem.Decode(cfg.PrivateKey)
	if block == nil || block.Type != "PRIVATE KEY" || len(bytes.TrimSpace(rest)) != 0 {
		return nil, errors.New("invalid APNs signing configuration")
	}
	raw, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, errors.New("invalid APNs signing configuration")
	}
	key, ok := raw.(*ecdsa.PrivateKey)
	if !ok || key.Curve != elliptic.P256() || cfg.TeamID == "" || cfg.KeyID == "" || len(cfg.EncryptionKey) != 32 || len(cfg.Topics) == 0 || (cfg.Environment != "development" && cfg.Environment != "production") {
		return nil, errors.New("invalid APNs configuration")
	}
	blockCipher, err := aes.NewCipher(cfg.EncryptionKey)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(blockCipher)
	if err != nil {
		return nil, err
	}
	signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.ES256, Key: key}, (&jose.SignerOptions{}).WithType("JWT").WithHeader("kid", cfg.KeyID))
	if err != nil {
		return nil, err
	}
	if cfg.HTTPClient == nil {
		cfg.HTTPClient = &http.Client{Timeout: 10 * time.Second}
	}
	client := *cfg.HTTPClient
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	if client.Timeout == 0 {
		client.Timeout = 10 * time.Second
	}
	if cfg.Endpoint == "" {
		cfg.Endpoint = "https://api.push.apple.com"
		if cfg.Environment == "development" {
			cfg.Endpoint = "https://api.sandbox.push.apple.com"
		}
	}
	if cfg.Clock == nil {
		cfg.Clock = time.Now
	}
	topics := map[string]bool{}
	for _, topic := range cfg.Topics {
		if topic == "" {
			return nil, errors.New("invalid APNs topic")
		}
		topics[topic] = true
	}
	return &Client{environment: cfg.Environment, topics: topics, teamID: cfg.TeamID, signer: signer, cipher: aead, http: &client, endpoint: strings.TrimRight(cfg.Endpoint, "/"), clock: cfg.Clock}, nil
}

func (c *Client) Available(topic, environment string) bool {
	return c != nil && c.environment == environment && c.topics[topic]
}

func ValidToken(token string) bool {
	decoded, err := hex.DecodeString(token)
	return err == nil && len(decoded) > 0 && len(decoded) <= 512
}

func (c *Client) authorization() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := c.clock()
	if c.assertion != "" && now.Sub(c.issued) >= 0 && now.Sub(c.issued) < 50*time.Minute {
		return c.assertion, nil
	}
	raw, _ := json.Marshal(map[string]any{"iss": c.teamID, "iat": now.Unix()})
	signed, err := c.signer.Sign(raw)
	if err != nil {
		return "", ErrUnavailable
	}
	assertion, err := signed.CompactSerialize()
	if err != nil {
		return "", ErrUnavailable
	}
	c.assertion, c.issued = assertion, now
	return assertion, nil
}

func (c *Client) Send(ctx context.Context, topic, token, messageID string, payload []byte) (Result, error) {
	if !c.topics[topic] || !ValidToken(token) || !json.Valid(payload) || len(payload) > 4096 {
		return Result{}, ErrUnavailable
	}
	if _, err := uuid.Parse(messageID); err != nil {
		return Result{}, ErrUnavailable
	}
	assertion, err := c.authorization()
	if err != nil {
		return Result{}, err
	}
	req, err := http.NewRequestWithContext(ctx, "POST", c.endpoint+"/3/device/"+token, bytes.NewReader(payload))
	if err != nil {
		return Result{}, ErrUnavailable
	}
	req.Header.Set("Authorization", "bearer "+assertion)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apns-topic", topic)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	req.Header.Set("apns-id", messageID)
	req.Header.Set("apns-collapse-id", messageID)
	req.Header.Set("apns-expiration", strconv.FormatInt(c.clock().Add(10*time.Minute).Unix(), 10))
	response, err := c.http.Do(req)
	if err != nil {
		return Result{}, ErrUnavailable
	}
	defer response.Body.Close()
	if response.StatusCode == 200 {
		return Result{Accepted: true}, nil
	}
	var failure struct {
		Reason string `json:"reason"`
	}
	json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&failure)
	invalid := (response.StatusCode == 410 && failure.Reason == "Unregistered") || (response.StatusCode == 400 && (failure.Reason == "BadDeviceToken" || failure.Reason == "DeviceTokenNotForTopic"))
	return Result{InvalidToken: invalid, Retryable: response.StatusCode == 429 || response.StatusCode >= 500}, nil
}

func (c *Client) Seal(userID, deviceID, topic, token string) ([]byte, error) {
	nonce := make([]byte, c.cipher.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	return c.cipher.Seal(nonce, nonce, []byte(token), []byte(userID+"\x00push\x00"+deviceID+"\x00"+topic+"\x00"+c.environment)), nil
}

func (c *Client) Open(userID, deviceID, topic string, sealed []byte) (string, error) {
	n := c.cipher.NonceSize()
	if len(sealed) < n {
		return "", ErrUnavailable
	}
	value, err := c.cipher.Open(nil, sealed[:n], sealed[n:], []byte(userID+"\x00push\x00"+deviceID+"\x00"+topic+"\x00"+c.environment))
	if err != nil {
		return "", ErrUnavailable
	}
	return string(value), nil
}
