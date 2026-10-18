package billing_test

import (
	"github.com/google/uuid"
	"github.com/turinglabsorg/makeet/backend/internal/billing"
	"github.com/turinglabsorg/makeet/backend/internal/testbilling"
	"strings"
	"testing"
	"time"
)

func TestSignedTransactionTrustAndClaims(t *testing.T) {
	now := time.Now()
	issuer := testbilling.New(t, now)
	purchase := testbilling.Purchase(uuid.NewString(), now)
	if _, err := issuer.Verifier.Transaction(issuer.Sign(t, purchase), now); err != nil {
		t.Fatal(err)
	}
	prod, err := billing.New(false)
	if err != nil {
		t.Fatal(err)
	}
	raw := issuer.Sign(t, purchase)
	if _, err = prod.Transaction(raw, now); err == nil {
		t.Fatal("trusted fixture root in production")
	}
	other := testbilling.New(t, now)
	if _, err = other.Verifier.Transaction(raw, now); err == nil {
		t.Fatal("trusted unrecognized root")
	}
	for _, mutate := range []func(*billing.Transaction){
		func(p *billing.Transaction) { p.BundleID = "other" }, func(p *billing.Transaction) { p.ProductID = "other" },
		func(p *billing.Transaction) { p.Environment = "Xcode" }, func(p *billing.Transaction) { p.AccountToken = "not-uuid" },
		func(p *billing.Transaction) { p.Ownership = "FAMILY_SHARED" }, func(p *billing.Transaction) { p.SignedDate = now.Add(time.Hour).UnixMilli() },
		func(p *billing.Transaction) { p.ExpiresDate = p.PurchaseDate }, func(p *billing.Transaction) { p.PurchaseDate = p.SignedDate + 1 },
	} {
		value := purchase
		mutate(&value)
		if _, err = issuer.Verifier.Transaction(issuer.Sign(t, value), now); err == nil {
			t.Fatal("invalid purchase accepted")
		}
	}
	parts := strings.Split(raw, ".")
	parts[2] = strings.Repeat("A", 86)
	if _, err = issuer.Verifier.Transaction(strings.Join(parts, "."), now); err == nil {
		t.Fatal("forged signature accepted")
	}
	if _, err = issuer.Verifier.Transaction(raw, now.AddDate(4, 0, 0)); err != nil {
		t.Fatal("historical signature must validate at its signed date", err)
	}
}
