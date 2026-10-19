package api_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/turinglabsorg/makeet/backend/internal/api"
	"github.com/turinglabsorg/makeet/backend/internal/identity"
	"github.com/turinglabsorg/makeet/backend/internal/store"
	"github.com/turinglabsorg/makeet/backend/internal/testidentity"
)

type fixture struct {
	t      *testing.T
	db     *sql.DB
	server *httptest.Server
	issuer *testidentity.Issuer
	apple  *testidentity.Apple
	push   *testidentity.Push
	api    *api.Server
	now    time.Time
	path   string
}
type session struct {
	Access  string `json:"access_token"`
	Refresh string `json:"refresh_token"`
	User    struct {
		ID string `json:"id"`
	} `json:"user"`
}

func setup(t *testing.T) *fixture {
	return setupRelay(t, false)
}

func setupRelay(t *testing.T, trusted bool) *fixture {
	t.Helper()
	f := &fixture{t: t, issuer: testidentity.New(t), now: time.Now(), path: filepath.Join(t.TempDir(), "makeet.sqlite")}
	db, err := store.Open(f.path)
	if err != nil {
		t.Fatal(err)
	}
	f.db = db
	f.apple = testidentity.NewApple(t)
	f.push = testidentity.NewPush(t)
	provider := identity.New(context.Background(), f.issuer.Server.URL, f.issuer.Server.URL, []string{"native-client"})
	f.api = api.New(db, api.Config{Apple: f.apple.Client, Push: f.push.Client, Providers: map[string]identity.Verifier{"google": provider, "apple": provider}, Clock: func() time.Time { return f.now }, TrustRelay: trusted})
	f.server = httptest.NewServer(f.api.Handler())
	t.Cleanup(func() { f.server.Close(); f.db.Close() })
	return f
}
func (f *fixture) request(method, path, token string, body any, status int) []byte {
	return f.requestProtocol(method, path, token, body, status, "2")
}
func (f *fixture) requestProtocol(method, path, token string, body any, status int, version string) []byte {
	f.t.Helper()
	var b bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&b).Encode(body); err != nil {
			f.t.Fatal(err)
		}
	}
	req, _ := http.NewRequest(method, f.server.URL+path, &b)
	req.Header.Set("Content-Type", "application/json")
	if version != "" {
		req.Header.Set("X-Makeet-Sync-Version", version)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := f.server.Client().Do(req)
	if err != nil {
		f.t.Fatal(err)
	}
	defer res.Body.Close()
	var out bytes.Buffer
	out.ReadFrom(res.Body)
	if res.StatusCode != status {
		f.t.Fatalf("%s %s: status %d, expected %d", method, path, res.StatusCode, status)
	}
	return out.Bytes()
}
func (f *fixture) challenge(provider string) (string, string) {
	var c struct{ ID, Nonce string }
	json.Unmarshal(f.request("POST", "/v1/auth/challenges", "", map[string]string{"provider": provider}, 201), &c)
	return c.ID, c.Nonce
}
func (f *fixture) login(provider, subject string) session {
	f.t.Helper()
	id, nonce := f.challenge(provider)
	var s session
	token := f.issuer.Token(f.t, subject, "native-client", nonce, nil)
	json.Unmarshal(f.request("POST", "/v1/auth/exchange", "", map[string]string{"provider": provider, "challenge_id": id, "id_token": token, "authorization_code": token}, 200), &s)
	if s.Access == "" || s.Refresh == "" || s.User.ID == "" {
		f.t.Fatal("missing session")
	}
	return s
}
func habit(id string, rev int64) api.Record {
	raw, _ := json.Marshal(map[string]any{"name": "Water", "symbol": "drop", "color_index": 1, "target": 8, "step": 1, "unit": "glasses", "created_at": "2026-01-01T00:00:00Z", "time_zone_id": "Europe/Rome", "preferred_hour": 10, "duration_minutes": 5, "archived": false})
	return api.Record{Kind: "habit", ID: id, Revision: rev, Data: raw}
}
func activity(id, parent string) api.Record {
	raw, _ := json.Marshal(map[string]any{"habit_id": parent, "amount": 1, "timestamp": "2026-10-16T08:00:00Z", "source": "app"})
	return api.Record{Kind: "activity", ID: id, Data: raw}
}
func (f *fixture) sync(s session, cursor int64, changes []api.Record) api.SyncResponse {
	f.t.Helper()
	var out api.SyncResponse
	json.Unmarshal(f.request("POST", "/v1/sync", s.Access, api.SyncRequest{Cursor: cursor, MutationID: uuid.NewString(), Changes: changes}, 200), &out)
	return out
}
func TestRegistrationChallengeAndIdentityIsolation(t *testing.T) {
	f := setup(t)
	a := f.login("google", "one")
	again := f.login("google", "one")
	b := f.login("google", "two")
	apple := f.login("apple", "one")
	if a.User.ID != again.User.ID || a.User.ID == b.User.ID || a.User.ID == apple.User.ID {
		t.Fatal("provider subject ownership violated")
	}
	id, nonce := f.challenge("google")
	body := map[string]string{"provider": "google", "challenge_id": id, "id_token": f.issuer.Token(t, "one", "native-client", nonce, nil)}
	f.request("POST", "/v1/auth/exchange", "", body, 200)
	f.request("POST", "/v1/auth/exchange", "", body, 401)
	id, nonce = f.challenge("google")
	f.request("POST", "/v1/auth/exchange", "", map[string]string{"provider": "google", "challenge_id": id, "id_token": f.issuer.Token(t, "one", "native-client", nonce+"wrong", nil)}, 401)
	id, nonce = f.challenge("google")
	f.now = f.now.Add(6 * time.Minute)
	f.request("POST", "/v1/auth/exchange", "", map[string]string{"provider": "google", "challenge_id": id, "id_token": f.issuer.Token(t, "one", "native-client", nonce, nil)}, 401)
	f.request("GET", "/v1/me", "", nil, 401)
}
func TestSessionRotationReplayLogoutAndExpiry(t *testing.T) {
	f := setup(t)
	s := f.login("google", "one")
	var rotated session
	json.Unmarshal(f.request("POST", "/v1/auth/refresh", "", map[string]string{"refresh_token": s.Refresh}, 200), &rotated)
	f.request("GET", "/v1/me", rotated.Access, nil, 200)
	f.request("POST", "/v1/auth/refresh", "", map[string]string{"refresh_token": s.Refresh}, 401)
	f.request("GET", "/v1/me", rotated.Access, nil, 401)
	other := f.login("google", "one")
	f.request("POST", "/v1/auth/logout", other.Access, nil, 204)
	f.request("GET", "/v1/me", other.Access, nil, 401)
	expiring := f.login("google", "one")
	f.now = f.now.Add(16 * time.Minute)
	f.request("GET", "/v1/me", expiring.Access, nil, 401)
	f.now = f.now.Add(31 * 24 * time.Hour)
	f.request("POST", "/v1/auth/refresh", "", map[string]string{"refresh_token": expiring.Refresh}, 401)
}
func TestSyncAtomicConflictsIsolationAndRetry(t *testing.T) {
	f := setup(t)
	a := f.login("google", "a")
	b := f.login("google", "b")
	hid := uuid.NewString()
	aid := uuid.NewString()
	req := api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{activity(aid, strings.ToUpper(hid)), habit(strings.ToUpper(hid), 0)}}
	raw := f.request("POST", "/v1/sync", a.Access, req, 200)
	var out api.SyncResponse
	json.Unmarshal(raw, &out)
	if len(out.Applied) != 2 || out.Applied[0].ID != hid || out.Applied[0].Revision != 1 {
		t.Fatal("mixed batch/canonicalization failed")
	}
	retried := f.request("POST", "/v1/sync", a.Access, req, 200)
	if !bytes.Equal(bytes.TrimSpace(raw), bytes.TrimSpace(retried)) {
		t.Fatal("retry changed response")
	}
	req.Changes = []api.Record{habit(hid, 1)}
	f.request("POST", "/v1/sync", a.Access, req, 409)
	if got := f.sync(b, 0, nil); len(got.Changes) != 0 {
		t.Fatal("cross-account read")
	}
	f.request("POST", "/v1/sync", b.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{activity(uuid.NewString(), hid)}}, 400)
	another := uuid.NewString()
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{habit(hid, 0), habit(another, 0)}}, 409)
	if got := f.sync(a, out.Cursor, nil); len(got.Changes) != 0 {
		t.Fatal("conflicting batch partially applied")
	}
	f.sync(a, out.Cursor, []api.Record{{Kind: "activity", ID: aid, Revision: 1, Deleted: true}})
	tombstones := f.sync(a, out.Cursor, nil)
	if len(tombstones.Changes) != 1 || !tombstones.Changes[0].Deleted {
		t.Fatal("missing tombstone")
	}
	// A fresh installation reads the same retained history after the database reopens.
	f.db.Close()
	db, err := store.Open(f.path)
	if err != nil {
		t.Fatal(err)
	}
	f.db = db
	var count int
	if err = db.QueryRow("SELECT count(*) FROM records WHERE user_id=?", a.User.ID).Scan(&count); err != nil || count != 2 {
		t.Fatal("persistence failed")
	}
}
func TestSyncPaginationAndAccountDeletion(t *testing.T) {
	f := setup(t)
	a := f.login("google", "a")
	b := f.login("google", "b")
	for batch := 0; batch < 3; batch++ {
		changes := []api.Record{}
		for n := 0; n < 90; n++ {
			changes = append(changes, habit(uuid.NewString(), 0))
		}
		f.sync(a, 0, changes)
	}
	page := f.sync(a, 0, nil)
	if len(page.Changes) != 200 || !page.HasMore {
		t.Fatal("first page")
	}
	next := f.sync(a, page.Cursor, nil)
	if len(next.Changes) != 70 || next.HasMore {
		t.Fatal("next page")
	}
	f.request("DELETE", "/v1/me", a.Access, map[string]string{"confirmation": "wrong"}, 400)
	f.request("DELETE", "/v1/me", a.Access, map[string]string{"confirmation": "DELETE"}, 204)
	f.request("GET", "/v1/me", a.Access, nil, 401)
	f.request("GET", "/v1/me", b.Access, nil, 200)
	for _, table := range []string{"identities", "sessions", "records", "changes", "batches"} {
		var n int
		f.db.QueryRow("SELECT count(*) FROM "+table+" WHERE user_id=?", a.User.ID).Scan(&n)
		if n != 0 {
			t.Fatalf("remaining %s", table)
		}
	}
	var n int
	f.db.QueryRow("SELECT count(*) FROM access_tokens").Scan(&n)
	if n != 1 {
		t.Fatal("orphaned access tokens")
	}
}
func TestValidationAndClosedProvider(t *testing.T) {
	f := setup(t)
	s := f.login("google", "one")
	f.request("POST", "/v1/auth/challenges", "", map[string]string{"provider": "password"}, 503)
	duplicate := uuid.NewString()
	f.request("POST", "/v1/sync", s.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{habit(duplicate, 0), habit(strings.ToUpper(duplicate), 0)}}, 400)
	f.request("POST", "/v1/sync", s.Access, api.SyncRequest{Cursor: -1}, 400)
	invalid := habit(uuid.NewString(), 0)
	invalid.Data = json.RawMessage(`{"name":"x","target":-1}`)
	f.request("POST", "/v1/sync", s.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{invalid}}, 400)
}

func TestAppleGrantEncryptionBindingAndDeletion(t *testing.T) {
	f := setup(t)
	id, nonce := f.challenge("apple")
	identityToken := f.issuer.Token(t, "apple-user", "native-client", nonce, nil)
	otherToken := f.issuer.Token(t, "another-user", "native-client", nonce, nil)
	body := map[string]string{"provider": "apple", "challenge_id": id, "id_token": identityToken}
	f.request("POST", "/v1/auth/exchange", "", body, 401)
	body["authorization_code"] = otherToken
	f.request("POST", "/v1/auth/exchange", "", body, 401)
	body["authorization_code"] = identityToken
	var s session
	json.Unmarshal(f.request("POST", "/v1/auth/exchange", "", body, 200), &s)
	var sealed []byte
	var audience string
	if err := f.db.QueryRow("SELECT audience,token FROM provider_grants WHERE user_id=?", s.User.ID).Scan(&audience, &sealed); err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(sealed, []byte("fixture-apple-refresh")) {
		t.Fatal("provider token stored in plaintext")
	}
	if _, err := f.apple.Client.Open("another-account", audience, sealed); err == nil {
		t.Fatal("ciphertext usable by another account")
	}
	if _, err := f.apple.Client.Open(s.User.ID, "another-client", sealed); err == nil {
		t.Fatal("ciphertext usable for another client")
	}
	f.sync(s, 0, []api.Record{habit(uuid.NewString(), 0)})
	f.apple.RevokeFailure.Store(true)
	f.request("DELETE", "/v1/me", s.Access, map[string]string{"confirmation": "DELETE"}, 503)
	f.request("GET", "/v1/me", s.Access, nil, 200)
	if result := f.sync(s, 0, nil); len(result.Changes) != 1 {
		t.Fatal("failed revocation lost account data")
	}
	f.apple.RevokeFailure.Store(false)
	f.request("DELETE", "/v1/me", s.Access, map[string]string{"confirmation": "DELETE"}, 204)
	if f.apple.Revocations.Load() != 1 {
		t.Fatal("provider authorization was not revoked")
	}
	f.request("GET", "/v1/me", s.Access, nil, 401)
	for _, table := range []string{"users", "identities", "provider_grants", "sessions", "records", "changes", "batches"} {
		var count int
		if err := f.db.QueryRow("SELECT COUNT(*) FROM " + table).Scan(&count); err != nil {
			t.Fatal(err)
		}
		if count != 0 {
			t.Fatalf("retained %s after deletion", table)
		}
	}
}

func TestAppleDisabledWithoutRevocationConfiguration(t *testing.T) {
	f := setup(t)
	provider := identity.New(context.Background(), f.issuer.Server.URL, f.issuer.Server.URL, []string{"native-client"})
	server := httptest.NewServer(api.New(f.db, api.Config{Providers: map[string]identity.Verifier{"apple": provider}}).Handler())
	defer server.Close()
	f.server.Close()
	f.server = server
	var config struct{ Providers []string }
	if err := json.Unmarshal(f.request("GET", "/v1/config", "", nil, 200), &config); err != nil {
		t.Fatal(err)
	}
	if len(config.Providers) != 0 {
		t.Fatal("Apple advertised without revocation configuration")
	}
	f.request("POST", "/v1/auth/challenges", "", map[string]string{"provider": "apple"}, 503)
	f.request("POST", "/v1/auth/exchange", "", map[string]string{"provider": "apple"}, 503)
}
