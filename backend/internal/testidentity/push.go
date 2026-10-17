package testidentity

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/go-jose/go-jose/v4"
	"github.com/google/uuid"
	"github.com/turinglabsorg/makeet/backend/internal/push"
)

type Push struct {
	Client                    *push.Client
	Server                    *httptest.Server
	Status                    atomic.Int32
	Calls                     atomic.Int32
	mu                        sync.Mutex
	LastID, LastAuthorization string
	LastPayload               []byte
	BeforeRespond             func()
}

func NewPush(t *testing.T) *Push {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	encryption := make([]byte, 32)
	if _, err := rand.Read(encryption); err != nil {
		t.Fatal(err)
	}
	p := &Push{}
	p.Status.Store(200)
	p.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || !strings.HasPrefix(r.URL.Path, "/3/device/") || !push.ValidToken(strings.TrimPrefix(r.URL.Path, "/3/device/")) || r.Header.Get("apns-topic") != "org.turinglabs.makeet" || r.Header.Get("apns-push-type") != "alert" || r.Header.Get("apns-priority") != "10" {
			http.Error(w, "bad APNs request", 400)
			return
		}
		id := r.Header.Get("apns-id")
		expiry, _ := strconv.ParseInt(r.Header.Get("apns-expiration"), 10, 64)
		if _, err := uuid.Parse(id); err != nil || expiry < time.Now().Unix() || expiry > time.Now().Add(11*time.Minute).Unix() {
			http.Error(w, "bad APNs headers", 400)
			return
		}
		signed, err := jose.ParseSigned(strings.TrimPrefix(r.Header.Get("Authorization"), "bearer "), []jose.SignatureAlgorithm{jose.ES256})
		if err != nil {
			http.Error(w, "bad APNs authorization", 403)
			return
		}
		claimsRaw, err := signed.Verify(&key.PublicKey)
		if err != nil {
			http.Error(w, "bad APNs signature", 403)
			return
		}
		var claims struct {
			Iss string
			Iat int64
		}
		if json.Unmarshal(claimsRaw, &claims) != nil || claims.Iss != "fixture-team" || claims.Iat < time.Now().Add(-time.Hour).Unix() || signed.Signatures[0].Header.KeyID != "fixture-push-key" {
			http.Error(w, "bad APNs claims", 403)
			return
		}
		var payload json.RawMessage
		if json.NewDecoder(r.Body).Decode(&payload) != nil {
			http.Error(w, "bad payload", 400)
			return
		}
		p.Calls.Add(1)
		p.mu.Lock()
		p.LastID = id
		p.LastAuthorization = r.Header.Get("Authorization")
		p.LastPayload = append([]byte(nil), payload...)
		p.mu.Unlock()
		if p.BeforeRespond != nil {
			p.BeforeRespond()
		}
		status := int(p.Status.Load())
		w.WriteHeader(status)
		if status == 410 {
			json.NewEncoder(w).Encode(map[string]string{"reason": "Unregistered"})
		}
		if status == 400 {
			json.NewEncoder(w).Encode(map[string]string{"reason": "BadDeviceToken"})
		}
	}))
	t.Cleanup(p.Server.Close)
	p.Client, err = push.New(push.Config{TeamID: "fixture-team", KeyID: "fixture-push-key", Environment: "development", PrivateKey: pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), EncryptionKey: encryption, Topics: []string{"org.turinglabs.makeet"}, Endpoint: p.Server.URL})
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func (p *Push) Snapshot() (string, []byte, string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.LastID, append([]byte(nil), p.LastPayload...), p.LastAuthorization
}
