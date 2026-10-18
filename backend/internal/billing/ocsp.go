package billing

import (
	"bytes"
	"context"
	"crypto"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"errors"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"sync"
	"time"

	"golang.org/x/crypto/ocsp"
)

var ErrUnavailable = errors.New("App Store certificate status unavailable")

type certificateStatus struct {
	client *http.Client
	allow  func(string) bool
	mu     sync.Mutex
	cache  map[[32]byte]time.Time
}

func appleOCSPURL(raw string) bool {
	u, err := url.Parse(raw)
	return err == nil && u.User == nil && u.Fragment == "" && u.Port() == "" &&
		(u.Scheme == "http" || u.Scheme == "https") && (u.Hostname() == "ocsp.apple.com" || u.Hostname() == "ocsp2.apple.com")
}

func newCertificateStatus() *certificateStatus {
	return &certificateStatus{client: &http.Client{Timeout: 4 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}, allow: appleOCSPURL, cache: make(map[[32]byte]time.Time)}
}

func (c *certificateStatus) check(ctx context.Context, cert, issuer *x509.Certificate, now time.Time) error {
	key := sha256.Sum256(append(append([]byte{}, cert.Raw...), issuer.Raw...))
	c.mu.Lock()
	validUntil, cached := c.cache[key]
	c.mu.Unlock()
	if cached && now.Before(validUntil) {
		return nil
	}
	request, err := ocsp.CreateRequest(cert, issuer, &ocsp.RequestOptions{Hash: crypto.SHA256})
	if err != nil {
		return ErrInvalid
	}
	if len(cert.OCSPServer) == 0 {
		return ErrInvalid
	}
	for _, endpoint := range cert.OCSPServer {
		if !c.allow(endpoint) {
			continue
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(request))
		if err != nil {
			continue
		}
		req.Header.Set("Content-Type", "application/ocsp-request")
		req.Header.Set("Accept", "application/ocsp-response")
		res, err := c.client.Do(req)
		if err != nil {
			continue
		}
		raw, readErr := io.ReadAll(io.LimitReader(res.Body, 1<<20+1))
		res.Body.Close()
		if readErr != nil || res.StatusCode != http.StatusOK {
			continue
		}
		if len(raw) > 1<<20 {
			return ErrInvalid
		}
		response, err := ocsp.ParseResponseForCert(raw, cert, issuer)
		if err != nil || response.Status != ocsp.Good || response.SerialNumber.Cmp(cert.SerialNumber) != 0 || !matchesIssuer(response, issuer) {
			return ErrInvalid
		}
		if response.ThisUpdate.IsZero() || response.ProducedAt.IsZero() || response.NextUpdate.IsZero() ||
			response.ThisUpdate.After(now.Add(time.Minute)) || response.ProducedAt.After(now.Add(time.Minute)) ||
			response.ProducedAt.Before(response.ThisUpdate.Add(-time.Minute)) || !response.NextUpdate.After(now) ||
			!response.NextUpdate.After(response.ThisUpdate) {
			return ErrInvalid
		}
		if responder := response.Certificate; responder != nil && !responder.Equal(issuer) {
			authorized := false
			for _, usage := range responder.ExtKeyUsage {
				authorized = authorized || usage == x509.ExtKeyUsageOCSPSigning
			}
			if !authorized {
				return ErrInvalid
			}
			roots := x509.NewCertPool()
			roots.AddCert(issuer)
			if _, err := responder.Verify(x509.VerifyOptions{Roots: roots, CurrentTime: now, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageOCSPSigning}}); err != nil {
				return ErrInvalid
			}
		}
		c.mu.Lock()
		if len(c.cache) >= 256 {
			clear(c.cache)
		}
		c.cache[key] = minTime(now.Add(5*time.Minute), response.NextUpdate.Add(-time.Minute))
		c.mu.Unlock()
		return nil
	}
	return ErrUnavailable
}

func minTime(a, b time.Time) time.Time {
	if a.Before(b) {
		return a
	}
	return b
}

func matchesIssuer(response *ocsp.Response, issuer *x509.Certificate) bool {
	var data struct {
		Raw        asn1.RawContent
		Version    int `asn1:"optional,default:0,explicit,tag:0"`
		Responder  asn1.RawValue
		ProducedAt time.Time `asn1:"generalized"`
		Responses  []struct {
			ID struct {
				Algorithm pkix.AlgorithmIdentifier
				Name      []byte
				Key       []byte
				Serial    *big.Int
			}
			Status     asn1.RawValue
			ThisUpdate time.Time        `asn1:"generalized"`
			NextUpdate time.Time        `asn1:"generalized,explicit,tag:0,optional"`
			Extensions []pkix.Extension `asn1:"explicit,tag:1,optional"`
		}
		Extensions []pkix.Extension `asn1:"explicit,tag:1,optional"`
	}
	if rest, err := asn1.Unmarshal(response.TBSResponseData, &data); err != nil || len(rest) != 0 || !response.IssuerHash.Available() {
		return false
	}
	var key struct {
		Algorithm pkix.AlgorithmIdentifier
		Value     asn1.BitString
	}
	if _, err := asn1.Unmarshal(issuer.RawSubjectPublicKeyInfo, &key); err != nil {
		return false
	}
	h := response.IssuerHash.New()
	h.Write(issuer.RawSubject)
	nameHash := h.Sum(nil)
	h.Reset()
	h.Write(key.Value.RightAlign())
	keyHash := h.Sum(nil)
	for _, entry := range data.Responses {
		if entry.ID.Serial != nil && entry.ID.Serial.Cmp(response.SerialNumber) == 0 {
			return bytes.Equal(nameHash, entry.ID.Name) && bytes.Equal(keyHash, entry.ID.Key)
		}
	}
	return false
}
