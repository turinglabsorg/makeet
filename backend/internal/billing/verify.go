package billing

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	_ "embed"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"strings"
	"time"

	"github.com/google/uuid"
)

//go:embed AppleRootCA-G3.cer
var appleRoot []byte

const Monthly = "org.turinglabs.makeet.plus.monthly"
const Yearly = "org.turinglabs.makeet.plus.yearly"

var ErrInvalid = errors.New("invalid App Store signature or transaction")

type Verifier struct {
	roots   *x509.CertPool
	Sandbox bool
}
type Transaction struct {
	ID             string `json:"transactionId"`
	OriginalID     string `json:"originalTransactionId"`
	BundleID       string `json:"bundleId"`
	ProductID      string `json:"productId"`
	AccountToken   string `json:"appAccountToken"`
	Environment    string `json:"environment"`
	Type           string `json:"type"`
	Ownership      string `json:"inAppOwnershipType"`
	PurchaseDate   int64  `json:"purchaseDate"`
	ExpiresDate    int64  `json:"expiresDate"`
	RevocationDate int64  `json:"revocationDate"`
	SignedDate     int64  `json:"signedDate"`
}
type Notification struct {
	UUID       string `json:"notificationUUID"`
	Type       string `json:"notificationType"`
	SignedDate int64  `json:"signedDate"`
	Data       struct {
		BundleID    string `json:"bundleId"`
		AppID       int64  `json:"appAppleId"`
		Environment string `json:"environment"`
		Transaction string `json:"signedTransactionInfo"`
	} `json:"data"`
}

func New(sandbox bool) (*Verifier, error) { return WithRoots([][]byte{appleRoot}, sandbox) }
func WithRoots(der [][]byte, sandbox bool) (*Verifier, error) {
	roots := x509.NewCertPool()
	for _, data := range der {
		cert, err := x509.ParseCertificate(data)
		if err != nil {
			return nil, err
		}
		roots.AddCert(cert)
	}
	return &Verifier{roots: roots, Sandbox: sandbox}, nil
}
func (v *Verifier) environment(env string) bool {
	return env == "Production" || (v.Sandbox && env == "Sandbox")
}
func (v *Verifier) Decode(raw string, out any, now time.Time) error {
	if len(raw) > 65536 {
		return ErrInvalid
	}
	parts := strings.Split(raw, ".")
	if len(parts) != 3 {
		return ErrInvalid
	}
	var header struct {
		Alg   string   `json:"alg"`
		Chain []string `json:"x5c"`
	}
	h, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil || json.Unmarshal(h, &header) != nil || header.Alg != "ES256" || len(header.Chain) != 3 {
		return ErrInvalid
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return ErrInvalid
	}
	var signed struct {
		Date int64 `json:"signedDate"`
	}
	if json.Unmarshal(payload, &signed) != nil || signed.Date <= 0 || signed.Date > now.Add(time.Minute).UnixMilli() {
		return ErrInvalid
	}
	certs := make([]*x509.Certificate, 3)
	for i, s := range header.Chain {
		der, e := base64.StdEncoding.DecodeString(s)
		if e != nil {
			return ErrInvalid
		}
		certs[i], err = x509.ParseCertificate(der)
		if err != nil {
			return ErrInvalid
		}
	}
	intermediate := x509.NewCertPool()
	intermediate.AddCert(certs[1])
	chains, err := certs[0].Verify(x509.VerifyOptions{Roots: v.roots, Intermediates: intermediate, CurrentTime: time.UnixMilli(signed.Date), KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}})
	if err != nil || len(chains) == 0 || len(chains[0]) != 3 || !hasOID(certs[0], asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}) || !hasOID(certs[1], asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}) {
		return ErrInvalid
	}
	key, ok := certs[0].PublicKey.(*ecdsa.PublicKey)
	if !ok || key.Curve != elliptic.P256() {
		return ErrInvalid
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(sig) != 64 {
		return ErrInvalid
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if !ecdsa.Verify(key, digest[:], new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])) {
		return ErrInvalid
	}
	if json.Unmarshal(payload, out) != nil {
		return ErrInvalid
	}
	return nil
}
func hasOID(cert *x509.Certificate, oid asn1.ObjectIdentifier) bool {
	for _, ext := range cert.Extensions {
		if ext.Id.Equal(oid) {
			return true
		}
	}
	return false
}
func (v *Verifier) Transaction(raw string, now time.Time) (Transaction, error) {
	var t Transaction
	if err := v.Decode(raw, &t, now); err != nil {
		return t, err
	}
	token, err := uuid.Parse(t.AccountToken)
	if err != nil || token == uuid.Nil || t.ID == "" || len(t.ID) > 64 || t.OriginalID == "" || len(t.OriginalID) > 64 || t.BundleID != "org.turinglabs.makeet" || !v.environment(t.Environment) || (t.ProductID != Monthly && t.ProductID != Yearly) || t.Type != "Auto-Renewable Subscription" || t.Ownership != "PURCHASED" || t.PurchaseDate <= 0 || t.PurchaseDate > t.SignedDate || t.ExpiresDate <= t.PurchaseDate || t.ExpiresDate > time.UnixMilli(t.PurchaseDate).AddDate(2, 0, 0).UnixMilli() {
		return t, ErrInvalid
	}
	t.AccountToken = token.String()
	return t, nil
}
func (v *Verifier) Notification(raw string, now time.Time) (Notification, error) {
	var n Notification
	if err := v.Decode(raw, &n, now); err != nil {
		return n, err
	}
	if _, err := uuid.Parse(n.UUID); err != nil || n.Data.BundleID != "org.turinglabs.makeet" || ((n.Data.Environment == "Production" || n.Data.AppID != 0) && n.Data.AppID != 6823557479) || !v.environment(n.Data.Environment) {
		return n, ErrInvalid
	}
	return n, nil
}
