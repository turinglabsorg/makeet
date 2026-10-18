package testbilling

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"github.com/turinglabsorg/makeet/backend/internal/billing"
	"math/big"
	"testing"
	"time"
)

type Issuer struct {
	Key      *ecdsa.PrivateKey
	Chain    []string
	Verifier *billing.Verifier
}

func New(t testing.TB, now time.Time) *Issuer {
	t.Helper()
	var parent *x509.Certificate
	var parentKey *ecdsa.PrivateKey
	var certs [][]byte
	for i := 0; i < 3; i++ {
		key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		template := &x509.Certificate{SerialNumber: big.NewInt(int64(i + 1)), Subject: pkix.Name{CommonName: "Makeet isolated App Store fixture"}, NotBefore: now.Add(-time.Hour), NotAfter: now.AddDate(3, 0, 0), BasicConstraintsValid: true, IsCA: i < 2, KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign}
		if i == 1 {
			template.ExtraExtensions = []pkix.Extension{{Id: asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}, Value: []byte{5, 0}}}
		}
		if i == 2 {
			template.KeyUsage = x509.KeyUsageDigitalSignature
			template.ExtraExtensions = []pkix.Extension{{Id: asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}, Value: []byte{5, 0}}}
		}
		if parent == nil {
			parent = template
			parentKey = key
		}
		der, err := x509.CreateCertificate(rand.Reader, template, parent, &key.PublicKey, parentKey)
		if err != nil {
			t.Fatal(err)
		}
		cert, err := x509.ParseCertificate(der)
		if err != nil {
			t.Fatal(err)
		}
		certs = append(certs, der)
		parent = cert
		parentKey = key
	}
	verifier, err := billing.WithRoots([][]byte{certs[0]}, true)
	if err != nil {
		t.Fatal(err)
	}
	return &Issuer{Key: parentKey, Verifier: verifier, Chain: []string{base64.StdEncoding.EncodeToString(certs[2]), base64.StdEncoding.EncodeToString(certs[1]), base64.StdEncoding.EncodeToString(certs[0])}}
}
func (i *Issuer) Sign(t testing.TB, value any) string {
	t.Helper()
	header, _ := json.Marshal(map[string]any{"alg": "ES256", "x5c": i.Chain})
	payload, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	message := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
	digest := sha256.Sum256([]byte(message))
	r, s, err := ecdsa.Sign(rand.Reader, i.Key, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return message + "." + base64.RawURLEncoding.EncodeToString(sig)
}
func Purchase(account string, now time.Time) billing.Transaction {
	return billing.Transaction{ID: "12345678", OriginalID: "12345678", BundleID: "org.turinglabs.makeet", ProductID: billing.Monthly, AccountToken: account, Environment: "Sandbox", Type: "Auto-Renewable Subscription", Ownership: "PURCHASED", PurchaseDate: now.Add(-time.Minute).UnixMilli(), ExpiresDate: now.AddDate(0, 1, 0).UnixMilli(), SignedDate: now.UnixMilli()}
}
