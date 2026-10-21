package mailer

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

type transport func(*http.Request) (*http.Response, error)

func (f transport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func TestResendUsesFixedOriginAndLocalizedBoundedMessage(t *testing.T) {
	c, err := New("fixture-key", "noreply@noreply.makeet.app")
	if err != nil {
		t.Fatal(err)
	}
	count := 0
	c.http.Transport = transport(func(r *http.Request) (*http.Response, error) {
		count++
		if r.URL.String() != "https://api.resend.com/emails" || r.Header.Get("Authorization") != "Bearer fixture-key" {
			t.Fatal("email origin or auth")
		}
		var body struct {
			From          string
			To            []string
			Subject, Text string
		}
		if json.NewDecoder(r.Body).Decode(&body) != nil || body.From != "Makeet <noreply@noreply.makeet.app>" || len(body.To) != 1 || body.To[0] != "qa@example.invalid" || !strings.Contains(body.Text, "12345678") || !strings.Contains(body.Text, "scade") {
			t.Fatal("localized code payload")
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"id":"receipt"}`)), Header: make(http.Header)}, nil
	})
	if err = c.SendCode(context.Background(), "qa@example.invalid", "12345678", "register", "it"); err != nil || count != 1 {
		t.Fatal("send failed")
	}
}
func TestResendRefusesRedirectAndInvalidSender(t *testing.T) {
	for _, from := range []string{"owner@example.com", "noreply@makeet.app", "noreply@noreply.makeet.app\r\nBcc: other@example.com"} {
		if _, err := New("fixture-key", from); err == nil {
			t.Fatal("invalid sender accepted")
		}
	}
	c, _ := New("fixture-key", "noreply@noreply.makeet.app")
	count := 0
	c.http.Transport = transport(func(r *http.Request) (*http.Response, error) {
		count++
		return &http.Response{StatusCode: 302, Header: http.Header{"Location": []string{"https://other.invalid"}}, Body: io.NopCloser(strings.NewReader("")), Request: r}, nil
	})
	if c.SendCode(context.Background(), "qa@example.invalid", "12345678", "recover", "en") == nil || count != 1 {
		t.Fatal("redirect followed")
	}
}
