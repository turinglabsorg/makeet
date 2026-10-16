package identity_test

import (
	"context"
	"github.com/turinglabsorg/makeet/backend/internal/identity"
	"github.com/turinglabsorg/makeet/backend/internal/testidentity"
	"testing"
	"time"
)

func TestSignedIdentityVerification(t *testing.T) {
	issuer := testidentity.New(t)
	verifier := identity.New(context.Background(), issuer.Server.URL, issuer.Server.URL, []string{"native-client", "server-client"})
	for _, tc := range []struct {
		name, aud, nonce string
		overrides        map[string]any
		valid            bool
	}{
		{name: "valid native", aud: "native-client", nonce: "challenge", valid: true},
		{name: "valid server", aud: "server-client", nonce: "challenge", valid: true},
		{name: "wrong audience", aud: "other", nonce: "challenge"},
		{name: "wrong nonce", aud: "native-client", nonce: "other"},
		{name: "missing nonce", aud: "native-client"},
		{name: "wrong issuer", aud: "native-client", nonce: "challenge", overrides: map[string]any{"iss": "https://attacker.test"}},
		{name: "expired", aud: "native-client", nonce: "challenge", overrides: map[string]any{"exp": time.Now().Add(-time.Hour).Unix()}},
		{name: "missing subject", aud: "native-client", nonce: "challenge", overrides: map[string]any{"sub": ""}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			token := issuer.Token(t, "person", tc.aud, tc.nonce, tc.overrides)
			who, err := verifier.Verify(context.Background(), token, "challenge")
			if (err == nil) != tc.valid {
				t.Fatalf("valid=%v error=%v", tc.valid, err)
			}
			if tc.valid && who.Subject != "person" {
				t.Fatal("wrong subject")
			}
		})
	}
	other := testidentity.New(t)
	if _, err := verifier.Verify(context.Background(), other.Token(t, "person", "native-client", "challenge", map[string]any{"iss": issuer.Server.URL}), "challenge"); err == nil {
		t.Fatal("accepted forged signature")
	}
}
