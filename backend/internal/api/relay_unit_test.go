package api

import (
	"net/http/httptest"
	"testing"
)

func TestRelayHeadersRequireExplicitTrustAndLoopbackPeer(t *testing.T) {
	req := httptest.NewRequest("GET", "http://api.makeet.app/v1/config", nil)
	req.Header.Set("X-Makeet-Client-IP", "203.0.113.2")
	s := &Server{cfg: Config{TrustRelay: true}}
	for _, remote := range []string{"203.0.113.1:1234", "[2001:db8::1]:1234"} {
		req.RemoteAddr = remote
		if s.clientAddress(req) != remote {
			t.Fatal("untrusted peer header accepted")
		}
	}
	req.RemoteAddr = "127.0.0.1:1234"
	if s.clientAddress(req) != "203.0.113.2" {
		t.Fatal("verified relay header ignored")
	}
	req.Header.Set("X-Makeet-Client-IP", "invalid")
	if s.clientAddress(req) != req.RemoteAddr {
		t.Fatal("malformed relay header accepted")
	}
}
