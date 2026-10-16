package apple

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/go-jose/go-jose/v4"
	"github.com/turinglabsorg/makeet/backend/internal/identity"
)

var ErrUnavailable = errors.New("apple authorization unavailable")
var ErrRejected = errors.New("apple authorization rejected")

type Client struct {
	teamID   string
	signer   jose.Signer
	cipher   cipher.AEAD
	http     *http.Client
	endpoint string
	clock    func() time.Time
}

type Config struct {
	TeamID, KeyID string
	PrivateKey    []byte
	EncryptionKey []byte
	HTTPClient    *http.Client
	Endpoint      string
	Clock         func() time.Time
}

func New(cfg Config) (*Client, error) {
	block, rest := pem.Decode(cfg.PrivateKey)
	if block == nil || len(strings.TrimSpace(string(rest))) != 0 || block.Type != "PRIVATE KEY" {
		return nil, errors.New("invalid Apple signing key")
	}
	raw, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, errors.New("invalid Apple signing key")
	}
	key, ok := raw.(*ecdsa.PrivateKey)
	if !ok || key.Curve != elliptic.P256() || cfg.TeamID == "" || cfg.KeyID == "" {
		return nil, errors.New("invalid Apple signing configuration")
	}
	if len(cfg.EncryptionKey) != 32 {
		return nil, errors.New("provider encryption key must contain 32 bytes")
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
	// Never forward provider secrets to an HTTP redirect destination.
	client := *cfg.HTTPClient
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	if client.Timeout == 0 {
		client.Timeout = 10 * time.Second
	}
	if cfg.Endpoint == "" {
		cfg.Endpoint = "https://appleid.apple.com/auth"
	}
	if cfg.Clock == nil {
		cfg.Clock = time.Now
	}
	return &Client{teamID: cfg.TeamID, signer: signer, cipher: aead, http: &client, endpoint: strings.TrimRight(cfg.Endpoint, "/"), clock: cfg.Clock}, nil
}

func (c *Client) clientSecret(audience string) (string, error) {
	now := c.clock()
	claims, err := json.Marshal(map[string]any{"iss": c.teamID, "sub": audience, "aud": "https://appleid.apple.com", "iat": now.Unix(), "exp": now.Add(5 * time.Minute).Unix()})
	if err != nil {
		return "", err
	}
	signed, err := c.signer.Sign(claims)
	if err != nil {
		return "", err
	}
	return signed.CompactSerialize()
}

func (c *Client) post(ctx context.Context, path string, form url.Values) ([]byte, error) {
	secret, err := c.clientSecret(form.Get("client_id"))
	if err != nil {
		return nil, ErrUnavailable
	}
	form.Set("client_secret", secret)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint+path, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, ErrUnavailable
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	response, err := c.http.Do(req)
	if err != nil {
		return nil, ErrUnavailable
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return nil, ErrUnavailable
	}
	if response.StatusCode == 400 {
		return nil, ErrRejected
	}
	if response.StatusCode != 200 {
		return nil, ErrUnavailable
	}
	return body, nil
}

func (c *Client) Exchange(ctx context.Context, code, nonce string, who identity.Identity, verifier identity.Verifier) (string, error) {
	if code == "" || len(code) > 4096 || who.Audience == "" {
		return "", ErrRejected
	}
	body, err := c.post(ctx, "/token", url.Values{"client_id": {who.Audience}, "code": {code}, "grant_type": {"authorization_code"}})
	if err != nil {
		return "", err
	}
	var result struct {
		RefreshToken string `json:"refresh_token"`
		IDToken      string `json:"id_token"`
	}
	if json.Unmarshal(body, &result) != nil || result.RefreshToken == "" || len(result.RefreshToken) > 8192 {
		return "", ErrUnavailable
	}
	verified, err := verifier.Verify(ctx, result.IDToken, nonce)
	if err != nil || verified.Subject != who.Subject || verified.Audience != who.Audience {
		return "", ErrRejected
	}
	return result.RefreshToken, nil
}

func (c *Client) Revoke(ctx context.Context, audience, token string) error {
	_, err := c.post(ctx, "/revoke", url.Values{"client_id": {audience}, "token": {token}, "token_type_hint": {"refresh_token"}})
	return err
}

func (c *Client) Seal(userID, audience, token string) ([]byte, error) {
	nonce := make([]byte, c.cipher.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	return c.cipher.Seal(nonce, nonce, []byte(token), []byte(userID+"\x00apple\x00"+audience)), nil
}
func (c *Client) Open(userID, audience string, sealed []byte) (string, error) {
	n := c.cipher.NonceSize()
	if len(sealed) < n {
		return "", ErrUnavailable
	}
	plaintext, err := c.cipher.Open(nil, sealed[:n], sealed[n:], []byte(userID+"\x00apple\x00"+audience))
	if err != nil {
		return "", ErrUnavailable
	}
	return string(plaintext), nil
}
