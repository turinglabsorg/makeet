package apple_test

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	"github.com/turinglabsorg/makeet/backend/internal/apple"
)

func configuration(t *testing.T) apple.Config {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return apple.Config{TeamID: "fixture-team", KeyID: "fixture-key", PrivateKey: pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), EncryptionKey: make([]byte, 32)}
}
func TestEncryptionIntegrityAndConfiguration(t *testing.T) {
	cfg := configuration(t)
	client, err := apple.New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	sealed, err := client.Seal("account", "client", "fixture-token")
	if err != nil {
		t.Fatal(err)
	}
	reopened, err := apple.New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if token, err := reopened.Open("account", "client", sealed); err != nil || token != "fixture-token" {
		t.Fatal("cannot reopen encrypted grant")
	}
	for _, value := range [][]byte{nil, []byte("short"), append([]byte(nil), sealed...)} {
		if len(value) == len(sealed) {
			value[len(value)-1] ^= 1
		}
		if _, err := client.Open("account", "client", value); err == nil {
			t.Fatal("invalid ciphertext accepted")
		}
	}
	cfg.EncryptionKey = make([]byte, 16)
	if _, err := apple.New(cfg); err == nil {
		t.Fatal("short encryption key accepted")
	}
	cfg = configuration(t)
	cfg.PrivateKey = []byte("invalid")
	if _, err := apple.New(cfg); err == nil {
		t.Fatal("invalid signing key accepted")
	}
}
func TestProviderRedirectDoesNotForwardCredentials(t *testing.T) {
	var forwarded atomic.Int32
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { forwarded.Add(1) }))
	defer target.Close()
	redirect := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, target.URL, http.StatusTemporaryRedirect)
	}))
	defer redirect.Close()
	cfg := configuration(t)
	cfg.Endpoint = redirect.URL
	client, err := apple.New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if err := client.Revoke(context.Background(), "native-client", "fixture-token"); err == nil {
		t.Fatal("redirect accepted")
	}
	if forwarded.Load() != 0 {
		t.Fatal("provider credentials forwarded to a different destination")
	}
}
