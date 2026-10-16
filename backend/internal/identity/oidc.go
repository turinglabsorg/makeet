package identity

import (
	"context"
	"crypto/subtle"
	"errors"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
)

type Identity struct {
	Subject string
	Email   string
}
type Verifier interface {
	Verify(context.Context, string, string) (Identity, error)
}
type Provider struct{ Verifiers []*oidc.IDTokenVerifier }

func New(ctx context.Context, issuer, jwks string, audiences []string) *Provider {
	keys := oidc.NewRemoteKeySet(ctx, jwks)
	result := &Provider{}
	for _, aud := range audiences {
		if aud = strings.TrimSpace(aud); aud != "" {
			result.Verifiers = append(result.Verifiers, oidc.NewVerifier(issuer, keys, &oidc.Config{ClientID: aud, SupportedSigningAlgs: []string{oidc.RS256}}))
		}
	}
	return result
}
func (p *Provider) Verify(ctx context.Context, raw, nonce string) (Identity, error) {
	for _, verifier := range p.Verifiers {
		token, err := verifier.Verify(ctx, raw)
		if err != nil {
			continue
		}
		if token.Subject == "" || nonce == "" || subtle.ConstantTimeCompare([]byte(token.Nonce), []byte(nonce)) != 1 {
			continue
		}
		var claims struct {
			Email string `json:"email"`
		}
		if err := token.Claims(&claims); err != nil {
			continue
		}
		return Identity{Subject: token.Subject, Email: claims.Email}, nil
	}
	return Identity{}, errors.New("invalid identity token")
}
