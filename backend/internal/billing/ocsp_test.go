package billing

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/ocsp"
)

type statusFixture struct {
	certs   []*x509.Certificate
	keys    []*ecdsa.PrivateKey
	now     time.Time
	server  *httptest.Server
	checker *certificateStatus
	calls   atomic.Int32
	mode    atomic.Int32
}

func newStatusFixture(t *testing.T) *statusFixture {
	t.Helper()
	f := &statusFixture{now: time.Now().UTC().Truncate(time.Second)}
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.calls.Add(1)
		if f.mode.Load() == 1 {
			w.WriteHeader(503)
			return
		}
		if f.mode.Load() == 2 {
			http.Redirect(w, r, "http://127.0.0.1:1/blocked", 302)
			return
		}
		raw, _ := io.ReadAll(r.Body)
		request, err := ocsp.ParseRequest(raw)
		if err != nil || r.Method != "POST" || r.Header.Get("Content-Type") != "application/ocsp-request" {
			w.WriteHeader(400)
			return
		}
		index := int(request.SerialNumber.Int64()) - 1
		if index < 1 || index > 2 {
			w.WriteHeader(400)
			return
		}
		issuer := f.certs[index-1]
		template := ocsp.Response{SerialNumber: request.SerialNumber, Status: ocsp.Good, ThisUpdate: f.now.Add(-time.Minute), NextUpdate: f.now.Add(time.Hour)}
		switch f.mode.Load() {
		case 3:
			template.Status = ocsp.Revoked
			template.RevokedAt = f.now.Add(-time.Minute)
		case 4:
			template.Status = ocsp.Unknown
		case 5:
			template.NextUpdate = f.now.Add(-time.Second)
		case 6:
			template.NextUpdate = time.Time{}
		case 7:
			template.ThisUpdate = f.now.Add(5 * time.Minute)
		case 8:
			template.SerialNumber = big.NewInt(999)
		case 9:
			copyIssuer := *issuer
			copyIssuer.RawSubject = f.certs[index].RawSubject
			issuer = &copyIssuer
		case 10:
			w.Write([]byte("invalid OCSP"))
			return
		}
		response, err := ocsp.CreateResponse(issuer, issuer, template, f.keys[index-1])
		if err != nil {
			w.WriteHeader(500)
			return
		}
		w.Header().Set("Content-Type", "application/ocsp-response")
		w.Write(response)
	}))
	t.Cleanup(f.server.Close)
	for i := 0; i < 3; i++ {
		key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		cert := &x509.Certificate{SerialNumber: big.NewInt(int64(i + 1)), Subject: pkix.Name{CommonName: []string{"isolated root", "isolated intermediate", "isolated transaction"}[i]}, NotBefore: f.now.Add(-time.Hour), NotAfter: f.now.AddDate(3, 0, 0), BasicConstraintsValid: true, IsCA: i < 2, KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign, OCSPServer: []string{f.server.URL}}
		if i == 1 {
			cert.ExtraExtensions = []pkix.Extension{{Id: asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 2, 1}, Value: []byte{5, 0}}}
		}
		if i == 2 {
			cert.KeyUsage = x509.KeyUsageDigitalSignature
			cert.ExtraExtensions = []pkix.Extension{{Id: asn1.ObjectIdentifier{1, 2, 840, 113635, 100, 6, 11, 1}, Value: []byte{5, 0}}}
		}
		parent, parentKey := cert, key
		if i > 0 {
			parent, parentKey = f.certs[i-1], f.keys[i-1]
		}
		der, err := x509.CreateCertificate(rand.Reader, cert, parent, &key.PublicKey, parentKey)
		if err != nil {
			t.Fatal(err)
		}
		parsed, err := x509.ParseCertificate(der)
		if err != nil {
			t.Fatal(err)
		}
		f.certs = append(f.certs, parsed)
		f.keys = append(f.keys, key)
	}
	f.checker = newCertificateStatus()
	f.checker.client = f.server.Client()
	f.checker.client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	f.checker.allow = func(raw string) bool { return raw == f.server.URL }
	return f
}
func (f *statusFixture) transaction(t *testing.T) string {
	t.Helper()
	header, _ := json.Marshal(map[string]any{"alg": "ES256", "x5c": []string{base64.StdEncoding.EncodeToString(f.certs[2].Raw), base64.StdEncoding.EncodeToString(f.certs[1].Raw), base64.StdEncoding.EncodeToString(f.certs[0].Raw)}})
	payload, _ := json.Marshal(Transaction{ID: "123456", OriginalID: "123456", BundleID: "org.turinglabs.makeet", ProductID: Monthly, AccountToken: uuid.NewString(), Environment: "Sandbox", Type: "Auto-Renewable Subscription", Ownership: "PURCHASED", PurchaseDate: f.now.Add(-time.Minute).UnixMilli(), ExpiresDate: f.now.Add(time.Hour).UnixMilli(), SignedDate: f.now.UnixMilli()})
	message := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
	digest := sha256.Sum256([]byte(message))
	r, s, err := ecdsa.Sign(rand.Reader, f.keys[2], digest[:])
	if err != nil {
		t.Fatal(err)
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return message + "." + base64.RawURLEncoding.EncodeToString(sig)
}
func TestOnlineCertificateStatusRejectsInvalidAndRetryableResponses(t *testing.T) {
	for _, mode := range []int32{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10} {
		t.Run(big.NewInt(int64(mode)).String(), func(t *testing.T) {
			f := newStatusFixture(t)
			f.mode.Store(mode)
			err := f.checker.check(context.Background(), f.certs[2], f.certs[1], f.now)
			if mode == 0 {
				if err != nil {
					t.Fatal(err)
				}
				return
			}
			if mode == 1 || mode == 2 {
				if !errors.Is(err, ErrUnavailable) {
					t.Fatalf("expected retryable status, got %v", err)
				}
			} else if !errors.Is(err, ErrInvalid) {
				t.Fatalf("expected rejection, got %v", err)
			}
		})
	}
}
func TestOnlineStatusCachesOnlyFreshGoodAndRespectsCancellation(t *testing.T) {
	f := newStatusFixture(t)
	for i := 0; i < 2; i++ {
		if err := f.checker.check(context.Background(), f.certs[2], f.certs[1], f.now); err != nil {
			t.Fatal(err)
		}
	}
	if f.calls.Load() != 1 {
		t.Fatal("good response was not cached")
	}
	f.mode.Store(1)
	if err := f.checker.check(context.Background(), f.certs[2], f.certs[1], f.now.Add(6*time.Minute)); !errors.Is(err, ErrUnavailable) {
		t.Fatal("stale cache masked responder failure", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := f.checker.check(ctx, f.certs[1], f.certs[0], f.now); !errors.Is(err, ErrUnavailable) {
		t.Fatal("cancelled verification did not fail closed", err)
	}
}
func TestTransactionRequiresBothOnlineCertificateStatuses(t *testing.T) {
	f := newStatusFixture(t)
	v, err := WithRoots([][]byte{f.certs[0].Raw}, true)
	if err != nil {
		t.Fatal(err)
	}
	v.status = f.checker
	raw := f.transaction(t)
	if _, err := v.TransactionContext(context.Background(), raw, f.now); err != nil {
		t.Fatal(err)
	}
	if f.calls.Load() != 2 {
		t.Fatal("leaf and intermediate were not checked")
	}
	f.checker.cache = make(map[[32]byte]time.Time)
	f.mode.Store(3)
	if _, err := v.TransactionContext(context.Background(), raw, f.now); !errors.Is(err, ErrInvalid) {
		t.Fatal("revoked transaction accepted", err)
	}
	f.mode.Store(1)
	if _, err := v.TransactionContext(context.Background(), raw, f.now); !errors.Is(err, ErrUnavailable) {
		t.Fatal("responder outage was not retryable", err)
	}
	if _, err := v.TransactionContext(context.Background(), raw, f.now.AddDate(4, 0, 0)); !errors.Is(err, ErrInvalid) {
		t.Fatal("online verification accepted an expired chain", err)
	}
}
func TestProductionStatusPolicyNeverUsesArbitraryResponders(t *testing.T) {
	for _, url := range []string{"http://127.0.0.1/", "https://ocsp.apple.com.evil.invalid/", "https://user@ocsp.apple.com/", "file:///etc/passwd", "http://ocsp.apple.com:8080/", "http://ocsp.apple.com/#fragment"} {
		if appleOCSPURL(url) {
			t.Fatal("untrusted endpoint", url)
		}
	}
	for _, url := range []string{"http://ocsp.apple.com/ocsp03", "https://ocsp2.apple.com/ocsp03"} {
		if !appleOCSPURL(url) {
			t.Fatal("expected Apple responder", url)
		}
	}
	v, err := New(true)
	if err != nil || v.status == nil {
		t.Fatal("runtime verification lacks online status")
	}
	f := newStatusFixture(t)
	f.checker.allow = appleOCSPURL
	if err := f.checker.check(context.Background(), f.certs[2], f.certs[1], f.now); !errors.Is(err, ErrUnavailable) || f.calls.Load() != 0 {
		t.Fatal("untrusted responder reached", err)
	}
	if strings.Contains(ErrUnavailable.Error(), f.server.URL) {
		t.Fatal("error leaked endpoint")
	}
}

func TestDelegatedOCSPResponderRequiresExplicitSigningPurposeAndCurrentValidity(t *testing.T) {
	for _, mode := range []string{"authorized", "missing-purpose", "wrong-purpose", "expired"} {
		t.Run(mode, func(t *testing.T) {
			f := newStatusFixture(t)
			issuer := f.certs[1]
			key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
			if err != nil {
				t.Fatal(err)
			}
			template := &x509.Certificate{SerialNumber: big.NewInt(50), Subject: pkix.Name{CommonName: "isolated OCSP responder"}, NotBefore: f.now.Add(-time.Hour), NotAfter: f.now.Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageOCSPSigning}}
			switch mode {
			case "missing-purpose":
				template.ExtKeyUsage = nil
			case "wrong-purpose":
				template.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}
			case "expired":
				template.NotAfter = f.now.Add(-time.Second)
			}
			der, err := x509.CreateCertificate(rand.Reader, template, issuer, &key.PublicKey, f.keys[1])
			if err != nil {
				t.Fatal(err)
			}
			responder, err := x509.ParseCertificate(der)
			if err != nil {
				t.Fatal(err)
			}
			raw, err := ocsp.CreateResponse(issuer, responder, ocsp.Response{SerialNumber: f.certs[2].SerialNumber, Status: ocsp.Good, ThisUpdate: f.now.Add(-time.Minute), NextUpdate: f.now.Add(time.Hour), Certificate: responder}, key)
			if err != nil {
				t.Fatal(err)
			}
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.Write(raw) }))
			defer server.Close()
			checker := newCertificateStatus()
			checker.client = server.Client()
			checker.allow = func(endpoint string) bool { return endpoint == server.URL }
			cert := *f.certs[2]
			cert.OCSPServer = []string{server.URL}
			err = checker.check(context.Background(), &cert, issuer, f.now)
			if mode == "authorized" && err != nil {
				t.Fatal("authorized responder rejected", err)
			}
			if mode != "authorized" && !errors.Is(err, ErrInvalid) {
				t.Fatal("unauthorized responder accepted", err)
			}
		})
	}
}
