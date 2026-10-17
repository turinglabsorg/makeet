package api_test

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
)

func relayChallenge(t *testing.T, f *fixture, address string, status int) {
	t.Helper()
	req, _ := http.NewRequest("POST", f.server.URL+"/v1/auth/challenges", strings.NewReader(`{"provider":"google"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Makeet-Client-IP", address)
	res, err := f.server.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != status {
		t.Fatalf("challenge status %d, expected %d", res.StatusCode, status)
	}
}
func TestTrustedRelayRateLimitsEachClientOverHTTP(t *testing.T) {
	f := setupRelay(t, true)
	for i := 0; i < 30; i++ {
		relayChallenge(t, f, "203.0.113.2", 201)
	}
	relayChallenge(t, f, "203.0.113.2", 429)
	relayChallenge(t, f, "2001:db8::2", 201)
	relayChallenge(t, f, "203.0.113.3", 201)
}
func TestUntrustedHeadersCannotResetRateLimitOverHTTP(t *testing.T) {
	f := setup(t)
	for i := 0; i < 30; i++ {
		relayChallenge(t, f, fmt.Sprintf("203.0.113.%d", i+1), 201)
	}
	relayChallenge(t, f, "203.0.113.99", 429)
}
