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
	"sync/atomic"
	"testing"
	"time"

	"github.com/go-jose/go-jose/v4"
	"github.com/turinglabsorg/makeet/backend/internal/apple"
)

type Apple struct {
	Client        *apple.Client
	Server        *httptest.Server
	RevokeFailure atomic.Bool
	Revocations   atomic.Int32
	LastRedirect  atomic.Value
}

func NewApple(t *testing.T) *Apple {
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
	a := &Apple{}
	a.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || r.ParseForm() != nil {
			http.Error(w, "bad request", 400)
			return
		}
		signed, err := jose.ParseSigned(r.Form.Get("client_secret"), []jose.SignatureAlgorithm{jose.ES256})
		if err != nil {
			http.Error(w, "bad client", 401)
			return
		}
		raw, err := signed.Verify(&key.PublicKey)
		if err != nil {
			http.Error(w, "bad signature", 401)
			return
		}
		var claims struct {
			Iss, Sub, Aud string
			Iat, Exp      int64
		}
		if json.Unmarshal(raw, &claims) != nil || claims.Iss != "fixture-team" || claims.Sub != r.Form.Get("client_id") || claims.Aud != "https://appleid.apple.com" || claims.Exp <= time.Now().Unix() || claims.Exp-claims.Iat != 300 || signed.Signatures[0].Header.KeyID != "fixture-key" {
			http.Error(w, "bad claims", 401)
			return
		}
		switch r.URL.Path {
		case "/token":
			a.LastRedirect.Store(r.Form.Get("redirect_uri"))
			if r.Form.Get("grant_type") != "authorization_code" || r.Form.Get("code") == "" {
				http.Error(w, "invalid grant", 400)
				return
			}
			json.NewEncoder(w).Encode(map[string]string{"id_token": r.Form.Get("code"), "refresh_token": "fixture-apple-refresh"})
		case "/revoke":
			if a.RevokeFailure.Load() {
				http.Error(w, "temporarily unavailable", 503)
				return
			}
			if r.Form.Get("token_type_hint") != "refresh_token" || r.Form.Get("token") == "" {
				http.Error(w, "invalid request", 400)
				return
			}
			a.Revocations.Add(1)
			w.WriteHeader(200)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(a.Server.Close)
	a.Client, err = apple.New(apple.Config{TeamID: "fixture-team", KeyID: "fixture-key", PrivateKey: pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), EncryptionKey: encryption, Endpoint: a.Server.URL})
	if err != nil {
		t.Fatal(err)
	}
	return a
}
