package api_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/turinglabsorg/makeet/backend/internal/api"
	"github.com/turinglabsorg/makeet/backend/internal/identity"
)

type codeMail struct {
	mu     sync.Mutex
	fail   bool
	codes  chan string
	failed chan struct{}
}

func (m *codeMail) SendCode(_ context.Context, email, code, kind, lang string) error {
	m.mu.Lock()
	failed := m.fail
	m.mu.Unlock()
	if failed {
		m.failed <- struct{}{}
		return errors.New("fixture unavailable")
	}
	m.codes <- code
	return nil
}
func (m *codeMail) next(t *testing.T) string {
	t.Helper()
	select {
	case code := <-m.codes:
		return code
	case <-time.After(5 * time.Second):
		t.Fatal("email fixture not called")
		return ""
	}
}
func passwordFixture(t *testing.T) (*fixture, *codeMail) {
	f := setup(t)
	m := &codeMail{codes: make(chan string, 8), failed: make(chan struct{}, 8)}
	provider := identity.New(context.Background(), f.issuer.Server.URL, f.issuer.Server.URL, []string{"native-client"})
	f.api = api.New(f.db, api.Config{Mailer: m, Apple: f.apple.Client, Providers: map[string]identity.Verifier{"google": provider, "apple": provider}, Clock: func() time.Time { return f.now }})
	f.server.Close()
	f.server = httptest.NewServer(f.api.Handler())
	return f, m
}

const testPassword = "fixture password 5 for testing"

func (f *fixture) startPassword(path, token, username, email string) string {
	var out struct {
		ID string `json:"request_id"`
	}
	json.Unmarshal(f.request("POST", path, token, map[string]string{"username": username, "email": email, "password": testPassword, "language": "it"}, 202), &out)
	if out.ID == "" {
		f.t.Fatal("missing request")
	}
	return out.ID
}
func (f *fixture) passwordLogin(identifier, password string, status int) session {
	var out session
	json.Unmarshal(f.request("POST", "/v1/auth/password/login", "", map[string]string{"identifier": identifier, "password": password}, status), &out)
	return out
}
func (f *fixture) confirmPassword(id, code, password, owner string, status int) {
	path := "/v1/auth/password/confirm"
	if owner != "" {
		path = "/v1/me/password/confirm"
	}
	f.request("POST", path, owner, map[string]string{"request_id": id, "code": code, "password": password}, status)
}
func TestPasswordRegistrationVerificationSessionsAndIsolation(t *testing.T) {
	f, m := passwordFixture(t)
	id := f.startPassword("/v1/auth/password/register", "", "First.User", "first@example.invalid")
	code := m.next(t)
	f.passwordLogin("first.user", testPassword, 401)
	f.confirmPassword(id, "wrong000", "", "", 400)
	f.confirmPassword(id, code, "", "", 200)
	f.confirmPassword(id, code, "", "", 400)
	a := f.passwordLogin("FIRST.USER", testPassword, 200)
	b := f.passwordLogin("first@example.invalid", testPassword, 200)
	if a.User.ID == "" || a.User.ID != b.User.ID {
		t.Fatal("username/email ownership mismatch")
	}
	f.request("GET", "/v1/me", a.Access, nil, 200)
	var stored string
	f.db.QueryRow("SELECT password_hash FROM password_credentials WHERE user_id=?", a.User.ID).Scan(&stored)
	if !strings.HasPrefix(stored, "argon2id$") || strings.Contains(stored, testPassword) {
		t.Fatal("password not protected")
	}
	other := f.login("google", "different")
	f.sync(a, 0, []api.Record{habit("aaaaaaaa-0000-4000-8000-000000000001", 0)})
	if len(f.sync(other, 0, nil).Changes) != 0 {
		t.Fatal("account isolation violated")
	}
	f.passwordLogin("first.user", "wrong", 401)
	duplicate := f.startPassword("/v1/auth/password/register", "", "first.user", "another@example.invalid")
	f.confirmPassword(duplicate, code, "", "", 400)
	f.request("POST", "/v1/auth/refresh", "", map[string]string{"refresh_token": a.Refresh}, 200)
	f.request("DELETE", "/v1/me", b.Access, map[string]string{"confirmation": "DELETE"}, 204)
	f.passwordLogin("first.user", testPassword, 401)
}
func TestPasswordRecoveryExpiryReplayAndSessionRevocation(t *testing.T) {
	f, m := passwordFixture(t)
	id := f.startPassword("/v1/auth/password/register", "", "recovery", "recover@example.invalid")
	code := m.next(t)
	f.confirmPassword(id, code, "", "", 200)
	a := f.passwordLogin("recovery", testPassword, 200)
	recover := func(identifier string) string {
		var v struct {
			ID string `json:"request_id"`
		}
		json.Unmarshal(f.request("POST", "/v1/auth/password/recover", "", map[string]string{"identifier": identifier, "language": "en"}, 202), &v)
		return v.ID
	}
	unknown := recover("unknown")
	f.confirmPassword(unknown, code, testPassword, "", 400)
	reset := recover("recovery")
	code = m.next(t)
	next := "replacement fixture password 77"
	f.confirmPassword(reset, code, next, "", 200)
	f.confirmPassword(reset, code, testPassword, "", 400)
	f.request("GET", "/v1/me", a.Access, nil, 401)
	f.request("POST", "/v1/auth/refresh", "", map[string]string{"refresh_token": a.Refresh}, 401)
	f.passwordLogin("recovery", testPassword, 401)
	f.passwordLogin("recovery", next, 200)
	reset = recover("recovery")
	code = m.next(t)
	f.now = f.now.Add(16 * time.Minute)
	f.confirmPassword(reset, code, testPassword, "", 400)
}
func TestPasswordEnrollmentRequiresSessionAndEmailProof(t *testing.T) {
	f, m := passwordFixture(t)
	a := f.login("apple", "original")
	b := f.login("google", "other")
	id := f.startPassword("/v1/me/password", a.Access, "linked.user", "linked@example.invalid")
	code := m.next(t)
	f.confirmPassword(id, code, "", "", 400)
	f.confirmPassword(id, code, "", b.Access, 400)
	f.confirmPassword(id, code, "", a.Access, 200)
	password := f.passwordLogin("linked.user", testPassword, 200)
	if password.User.ID != a.User.ID {
		t.Fatal("enrollment created a competing account")
	}
	f.request("GET", "/v1/me/password", b.Access, nil, 200)
	if got := string(f.request("GET", "/v1/me/password", b.Access, nil, 200)); strings.Contains(got, "linked.user") {
		t.Fatal("credentials disclosed across accounts")
	}
}
func TestPasswordCodesBoundedAndEmailFailureDoesNotCreateAccount(t *testing.T) {
	f, m := passwordFixture(t)
	id := f.startPassword("/v1/auth/password/register", "", "bounded", "bounded@example.invalid")
	code := m.next(t)
	wrong := "11111111"
	if code == wrong {
		wrong = "22222222"
	}
	for range 10 {
		f.confirmPassword(id, wrong, "", "", 400)
	}
	f.confirmPassword(id, code, "", "", 400)
	f.now = f.now.Add(time.Minute)
	m.mu.Lock()
	m.fail = true
	m.mu.Unlock()
	f.request("POST", "/v1/auth/password/register", "", map[string]string{"username": "failure", "email": "failure@example.invalid", "password": testPassword}, 202)
	select {
	case <-m.failed:
	case <-time.After(5 * time.Second):
		t.Fatal("email failure not exercised")
	}
	var n int
	f.db.QueryRow("SELECT COUNT(*) FROM users").Scan(&n)
	if n != 0 {
		t.Fatal("unverified account persisted")
	}
	for attempt := 0; attempt < 100; attempt++ {
		if err := f.db.QueryRow("SELECT COUNT(*) FROM password_requests WHERE email='failure@example.invalid'").Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n == 0 {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if n != 0 {
		t.Fatal("failed email code remained usable")
	}
}
func TestPasswordPendingProofSurvivesRestartAndNeverLinksByEmail(t *testing.T) {
	f, m := passwordFixture(t)
	provider := f.login("google", "provider-owner")
	var email string
	if err := f.db.QueryRow("SELECT email FROM users WHERE id=?", provider.User.ID).Scan(&email); err != nil {
		t.Fatal(err)
	}
	id := f.startPassword("/v1/auth/password/register", "", "independent", email)
	code := m.next(t)
	var proof, encoded string
	if err := f.db.QueryRow("SELECT code_hash,password_hash FROM password_requests WHERE id=?", id).Scan(&proof, &encoded); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(proof, code) || strings.Contains(encoded, testPassword) {
		t.Fatal("plaintext pending credential")
	}
	// Reconstruct the HTTP server over the same durable database before confirmation.
	f.server.Close()
	f.api = api.New(f.db, api.Config{Mailer: m, Clock: func() time.Time { return f.now }})
	f.server = httptest.NewServer(f.api.Handler())
	f.confirmPassword(id, code, "", "", 200)
	account := f.passwordLogin("independent", testPassword, 200)
	if account.User.ID == provider.User.ID {
		t.Fatal("provider account linked by matching email")
	}
	exported := f.request("GET", "/v1/me/export", account.Access, nil, 200)
	if strings.Contains(string(exported), encoded) || strings.Contains(string(exported), "code_hash") {
		t.Fatal("credential material in export")
	}
}

func TestPasswordDisabledAndBruteForceLimit(t *testing.T) {
	f := setup(t)
	f.passwordLogin("anyone", testPassword, 503)
	f, _ = passwordFixture(t)
	for range 10 {
		f.passwordLogin("missing", testPassword, 401)
	}
	f.passwordLogin("missing", testPassword, 429)
	f.now = f.now.Add(16 * time.Minute)
	f.passwordLogin("missing", testPassword, 401)
}

type blockedCodeMail struct{ started, release, done chan struct{} }

func (m *blockedCodeMail) SendCode(ctx context.Context, email, code, kind, language string) error {
	close(m.started)
	defer close(m.done)
	select {
	case <-m.release:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
func TestPasswordRecoveryResponseDoesNotWaitForProviderOrExposeExistence(t *testing.T) {
	f, m := passwordFixture(t)
	id := f.startPassword("/v1/auth/password/register", "", "private.user", "private@example.invalid")
	f.confirmPassword(id, m.next(t), "", "", 200)
	gate := &blockedCodeMail{started: make(chan struct{}), release: make(chan struct{}), done: make(chan struct{})}
	defer close(gate.release)
	f.server.Close()
	f.api = api.New(f.db, api.Config{Mailer: gate, Clock: func() time.Time { return f.now }})
	f.server = httptest.NewServer(f.api.Handler())
	known := f.request("POST", "/v1/auth/password/recover", "", map[string]string{"identifier": "private.user"}, 202)
	select {
	case <-gate.started:
	case <-time.After(5 * time.Second):
		t.Fatal("provider request not queued")
	}
	unknown := f.request("POST", "/v1/auth/password/recover", "", map[string]string{"identifier": "missing.user"}, 202)
	for _, body := range [][]byte{known, unknown} {
		var response map[string]string
		if json.Unmarshal(body, &response) != nil || len(response) != 1 || response["request_id"] == "" {
			t.Fatal("recovery disclosed identity state")
		}
	}
	select {
	case <-gate.done:
		t.Fatal("response waited for email provider")
	default:
	}
}
