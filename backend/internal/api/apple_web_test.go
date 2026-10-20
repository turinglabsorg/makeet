package api_test

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/turinglabsorg/makeet/backend/internal/api"
	"github.com/turinglabsorg/makeet/backend/internal/identity"
)

func setupAppleWeb(t *testing.T) *fixture {
	f := setup(t)
	f.server.Close()
	provider := identity.New(context.Background(), f.issuer.Server.URL, f.issuer.Server.URL, []string{"native-client", "other-client"})
	f.api = api.New(f.db, api.Config{Apple: f.apple.Client, AppleWebClientID: "native-client", Providers: map[string]identity.Verifier{"apple": provider}, Clock: func() time.Time { return f.now }})
	f.server = httptest.NewServer(f.api.Handler())
	return f
}

type webFlow struct {
	ID  string `json:"id"`
	URL string `json:"authorization_url"`
}

const fixtureVerifier = "qa-fixture-proof-01234567890123456789012345678901234567890123456789"

func (f *fixture) startWeb() (webFlow, string, string) {
	f.t.Helper()
	id, nonce := f.challenge("apple")
	digest := sha256.Sum256([]byte(fixtureVerifier))
	body := map[string]string{"challenge_id": id, "code_challenge": base64.RawURLEncoding.EncodeToString(digest[:]), "language": "it"}
	var flow webFlow
	if err := json.Unmarshal(f.request("POST", "/v1/auth/apple/start", "", body, 201), &flow); err != nil {
		f.t.Fatal(err)
	}
	return flow, id, nonce
}
func (f *fixture) callbackWeb(flow webFlow, token string, status int) string {
	f.t.Helper()
	u, _ := url.Parse(flow.URL)
	response, err := f.server.Client().PostForm(f.server.URL+"/v1/auth/apple/callback", url.Values{"state": {u.Query().Get("state")}, "id_token": {token}, "code": {token}})
	if err != nil {
		f.t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != status {
		f.t.Fatalf("callback status%d expected%d", response.StatusCode, status)
	}
	body, _ := io.ReadAll(response.Body)
	return string(body)
}

func TestAppleWebHandoffRequiresProofAndExchangesThroughExistingSessionService(t *testing.T) {
	f := setupAppleWeb(t)
	flow, challengeID, nonce := f.startWeb()
	u, err := url.Parse(flow.URL)
	if err != nil || u.Scheme != "https" || u.Host != "appleid.apple.com" || u.Path != "/auth/authorize" || u.Query().Get("nonce") != nonce || u.Query().Get("redirect_uri") != "https://api.makeet.app/v1/auth/apple/callback" || u.Query().Get("response_mode") != "form_post" {
		t.Fatal("invalid Apple authorization URL")
	}
	proof := map[string]string{"id": flow.ID, "code_verifier": fixtureVerifier}
	f.request("POST", "/v1/auth/apple/result", "", proof, 202)
	token := f.issuer.Token(t, "android-apple-user", "native-client", nonce, nil)
	html := f.callbackWeb(flow, token, 200)
	if !strings.Contains(html, "makeet://apple/complete") || !strings.Contains(html, "Torna a Makeet") || strings.Contains(html, token) || strings.Contains(html, flow.ID) {
		t.Fatal("callback must return to app without tokens or handoff identifiers")
	}
	f.request("POST", "/v1/auth/apple/result", "", map[string]string{"id": flow.ID, "code_verifier": strings.Repeat("z", 43)}, 404)
	var result map[string]string
	json.Unmarshal(f.request("POST", "/v1/auth/apple/result", "", proof, 200), &result)
	if result["id_token"] != token || result["authorization_code"] != token {
		t.Fatal("handoff lost authorization")
	}
	f.request("POST", "/v1/auth/apple/result", "", proof, 404)
	var account session
	json.Unmarshal(f.request("POST", "/v1/auth/exchange", "", map[string]string{"provider": "apple", "challenge_id": challengeID, "id_token": result["id_token"], "authorization_code": result["authorization_code"]}, 200), &account)
	if account.Access == "" || account.User.ID == "" {
		t.Fatal("no account session after valid Apple authorization")
	}
	if f.apple.LastRedirect.Load() != "https://api.makeet.app/v1/auth/apple/callback" {
		t.Fatal("web code exchange must preserve the registered redirect")
	}
	f.request("GET", "/v1/me", account.Access, nil, 200)
}

func TestAppleWebRejectsInvalidNonceAndAudienceAndCallbackReplay(t *testing.T) {
	f := setupAppleWeb(t)
	flow, _, nonce := f.startWeb()
	f.callbackWeb(flow, f.issuer.Token(t, "subject", "native-client", "wrong-nonce", nil), 401)
	f.callbackWeb(flow, f.issuer.Token(t, "subject", "other-client", nonce, nil), 401)
	token := f.issuer.Token(t, "subject", "native-client", nonce, nil)
	f.callbackWeb(flow, token, 200)
	f.callbackWeb(flow, token, 409)
}

func TestAppleWebExpiryAndCancellationCannotCreateSession(t *testing.T) {
	f := setupAppleWeb(t)
	flow, _, _ := f.startWeb()
	u, _ := url.Parse(flow.URL)
	response, err := f.server.Client().PostForm(f.server.URL+"/v1/auth/apple/callback", url.Values{"state": {u.Query().Get("state")}, "error": {"user_cancelled_authorize"}})
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()
	if response.StatusCode != 200 {
		t.Fatal("cancel must allow return to app")
	}
	f.request("POST", "/v1/auth/apple/result", "", map[string]string{"id": flow.ID, "code_verifier": fixtureVerifier}, 403)
	f.request("POST", "/v1/auth/apple/result", "", map[string]string{"id": flow.ID, "code_verifier": fixtureVerifier}, 404)
	flow, _, nonce := f.startWeb()
	f.now = f.now.Add(5 * time.Minute)
	f.callbackWeb(flow, f.issuer.Token(t, "subject", "native-client", nonce, nil), 400)
	f.request("POST", "/v1/auth/apple/result", "", map[string]string{"id": flow.ID, "code_verifier": fixtureVerifier}, 404)
	var count int
	f.db.QueryRow("SELECT COUNT(*) FROM users").Scan(&count)
	if count != 0 {
		t.Fatal("cancelled or expired handoff created a user")
	}
}

func TestAppleWebRemainsDisabledWithoutExplicitServiceConfiguration(t *testing.T) {
	f := setup(t)
	f.request("POST", "/v1/auth/apple/start", "", map[string]string{}, 503)
	f.request("POST", "/v1/auth/apple/result", "", map[string]string{}, 503)
	var config struct {
		Enabled bool `json:"apple_android_enabled"`
	}
	json.Unmarshal(f.request("GET", "/v1/config", "", nil, 200), &config)
	if config.Enabled {
		t.Fatal("Apple web sign-in must default off")
	}
}

func TestAppleWebRejectsDuplicateFlowAndMalformedProof(t *testing.T) {
	f := setupAppleWeb(t)
	_, challengeID, _ := f.startWeb()
	digest := sha256.Sum256([]byte(fixtureVerifier))
	f.request("POST", "/v1/auth/apple/start", "", map[string]string{"challenge_id": challengeID, "code_challenge": base64.RawURLEncoding.EncodeToString(digest[:])}, 409)
	f.request("POST", "/v1/auth/apple/start", "", map[string]string{"challenge_id": challengeID, "code_challenge": "invalid"}, 400)
	f.request("POST", "/v1/auth/apple/result", "", map[string]string{"id": "unknown", "code_verifier": "short"}, 400)
	f.request("POST", "/v1/auth/apple/callback", "", map[string]string{}, 415)
}
