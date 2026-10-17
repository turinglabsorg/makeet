package api_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/turinglabsorg/makeet/backend/internal/api"
)

func deviceBody(token string) map[string]any {
	return map[string]any{"installation_secret": base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32)), "token": token, "topic": "org.turinglabs.makeet", "environment": "development", "language": "it", "time_zone": "Europe/Rome", "reminders_enabled": false, "reminder_hour": 10, "reminder_minute": 0}
}
func (f *fixture) count(query string, args ...any) int {
	f.t.Helper()
	var n int
	if err := f.db.QueryRow(query, args...).Scan(&n); err != nil {
		f.t.Fatal(err)
	}
	return n
}
func TestDeviceOwnershipEncryptionAndAccountTransfer(t *testing.T) {
	f := setup(t)
	a := f.login("google", "a")
	b := f.login("google", "b")
	id := uuid.NewString()
	path := "/v1/devices/" + id
	token := strings.Repeat("ab", 32)
	body := deviceBody(token)
	f.request("PUT", path, "", body, 401)
	f.request("PUT", path, a.Access, body, 200)
	var encrypted []byte
	if err := f.db.QueryRow("SELECT token FROM devices WHERE id=?", id).Scan(&encrypted); err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(encrypted, []byte(token)) {
		t.Fatal("plaintext token persisted")
	}
	plain, err := f.push.Client.Open(a.User.ID, id, "org.turinglabs.makeet", encrypted)
	if err != nil || plain != token {
		t.Fatal("encrypted token unavailable")
	}
	wrong := deviceBody(token)
	wrong["installation_secret"] = base64.RawURLEncoding.EncodeToString(bytes.Repeat([]byte{8}, 32))
	f.request("PUT", path, b.Access, wrong, 409)
	proof := map[string]string{"installation_secret": body["installation_secret"].(string)}
	f.request("DELETE", path, b.Access, proof, 404)
	msg := uuid.NewString()
	proof["message_id"] = msg
	f.request("POST", path+"/test", a.Access, proof, 200)
	if f.count("SELECT confirmed_at FROM push_messages WHERE id=?", msg) != 0 {
		t.Fatal("acceptance reported as receipt")
	}
	if f.count("SELECT accepted_at FROM push_messages WHERE id=?", msg) == 0 {
		t.Fatal("missing acceptance")
	}
	f.request("POST", path+"/receipts", b.Access, proof, 404)
	f.request("POST", path+"/receipts", a.Access, proof, 204)
	f.request("PUT", path, b.Access, body, 200)
	if f.count("SELECT COUNT(*) FROM push_messages WHERE device_id=?", id) != 0 {
		t.Fatal("previous account messages retained")
	}
	f.request("POST", path+"/test", a.Access, proof, 404)
	f.request("POST", "/v1/auth/logout", b.Access, nil, 204)
	if f.count("SELECT COUNT(*) FROM devices WHERE id=?", id) != 0 {
		t.Fatal("logout retained device")
	}
}
func TestPushIdempotenceRetryAndRejectedToken(t *testing.T) {
	f := setup(t)
	a := f.login("google", "a")
	id := uuid.NewString()
	path := "/v1/devices/" + id
	body := deviceBody(strings.Repeat("cd", 32))
	f.request("PUT", path, a.Access, body, 200)
	proof := map[string]string{"installation_secret": body["installation_secret"].(string), "message_id": uuid.NewString()}
	f.push.Status.Store(503)
	f.request("POST", path+"/test", a.Access, proof, 200)
	f.request("POST", path+"/test", a.Access, proof, 200)
	if f.push.Calls.Load() != 1 {
		t.Fatal("idempotent retry resent immediately")
	}
	other := map[string]string{"installation_secret": proof["installation_secret"], "message_id": uuid.NewString()}
	f.request("POST", path+"/test", a.Access, other, 429)
	f.push.Status.Store(200)
	f.now = f.now.Add(time.Minute)
	f.api.TickPush(context.Background())
	if f.push.Calls.Load() != 2 || f.count("SELECT accepted_at FROM push_messages WHERE id=?", proof["message_id"]) == 0 {
		t.Fatal("retry did not complete")
	}
	f.request("POST", path+"/test", a.Access, proof, 200)
	if f.push.Calls.Load() != 2 {
		t.Fatal("accepted message resent")
	}
	f.push.Status.Store(410)
	f.now = f.now.Add(time.Minute)
	f.request("POST", path+"/test", a.Access, other, 503)
	if f.count("SELECT COUNT(*) FROM devices WHERE id=?", id) != 0 {
		t.Fatal("rejected token retained")
	}
}
func TestPushValidationTokenReplacementAndDeletion(t *testing.T) {
	f := setup(t)
	a := f.login("google", "a")
	b := f.login("google", "b")
	id := uuid.NewString()
	body := deviceBody(strings.Repeat("ef", 32))
	path := "/v1/devices/" + id
	for key, value := range map[string]any{"environment": "production", "topic": "other.app", "language": "xx", "time_zone": "invalid/zone", "token": "not-hex", "reminder_hour": 25, "installation_secret": "short"} {
		invalid := deviceBody(strings.Repeat("ef", 32))
		invalid[key] = value
		status := 400
		if key == "environment" || key == "topic" {
			status = 503
		}
		f.request("PUT", path, a.Access, invalid, status)
	}
	f.request("PUT", path, a.Access, body, 200)
	replacement := uuid.NewString()
	f.request("PUT", "/v1/devices/"+replacement, b.Access, body, 200)
	if f.count("SELECT COUNT(*) FROM devices WHERE user_id=?", a.User.ID) != 0 {
		t.Fatal("same token still attached to old user")
	}
	f.request("DELETE", "/v1/me", b.Access, map[string]string{"confirmation": "DELETE"}, 204)
	if f.count("SELECT COUNT(*) FROM devices") != 0 {
		t.Fatal("account deletion retained token")
	}
}
func TestDailyRemindersRespectCompletionLocalDayAndDeduplicate(t *testing.T) {
	f := setup(t)
	f.now = time.Date(2026, 10, 25, 9, 2, 0, 0, time.UTC)
	a := f.login("google", "a")
	id := uuid.NewString()
	body := deviceBody(strings.Repeat("12", 32))
	body["reminders_enabled"] = true
	f.request("PUT", "/v1/devices/"+id, a.Access, body, 200)
	f.api.TickPush(context.Background())
	if f.push.Calls.Load() != 0 {
		t.Fatal("reminder without habits")
	}
	h := habit(uuid.NewString(), 0)
	f.sync(a, 0, []api.Record{h})
	f.api.TickPush(context.Background())
	f.api.TickPush(context.Background())
	if f.push.Calls.Load() != 1 {
		t.Fatal("daily reminder not deduplicated")
	}
	_, payload, _ := f.push.Snapshot()
	if bytes.Contains(payload, []byte("Water")) || bytes.Contains(payload, []byte(a.User.ID)) {
		t.Fatal("private data in alert")
	}
	f.now = f.now.AddDate(0, 0, 1)
	json.Unmarshal(f.request("POST", "/v1/auth/refresh", "", map[string]string{"refresh_token": a.Refresh}, 200), &a)
	act := activity(uuid.NewString(), h.ID)
	act.Data = json.RawMessage(`{"habit_id":"` + h.ID + `","amount":8,"timestamp":"2026-10-26T08:00:00Z","source":"app"}`)
	f.sync(a, 0, []api.Record{act})
	f.api.TickPush(context.Background())
	if f.push.Calls.Load() != 1 {
		t.Fatal("completed habit reminder sent")
	}
	f.now = f.now.AddDate(0, 0, 1)
	f.api.TickPush(context.Background())
	if f.push.Calls.Load() != 2 {
		t.Fatal("new local day reminder missing")
	}
}
func TestRevokedSessionCannotReceivePendingPush(t *testing.T) {
	f := setup(t)
	a := f.login("google", "a")
	id := uuid.NewString()
	body := deviceBody(strings.Repeat("34", 32))
	path := "/v1/devices/" + id
	f.request("PUT", path, a.Access, body, 200)
	f.push.Status.Store(503)
	f.request("POST", path+"/test", a.Access, map[string]string{"installation_secret": body["installation_secret"].(string), "message_id": uuid.NewString()}, 200)
	f.request("POST", "/v1/auth/refresh", "", map[string]string{"refresh_token": a.Refresh}, 200)
	f.request("POST", "/v1/auth/refresh", "", map[string]string{"refresh_token": a.Refresh}, 401)
	f.now = f.now.Add(time.Minute)
	f.push.Status.Store(200)
	f.api.TickPush(context.Background())
	if f.push.Calls.Load() != 1 {
		t.Fatal("revoked session received push")
	}
}

func TestOldAPNsRejectionCannotRemoveRefreshedRegistration(t *testing.T) {
	f := setup(t)
	a := f.login("google", "a")
	id := uuid.NewString()
	path := "/v1/devices/" + id
	body := deviceBody(strings.Repeat("56", 32))
	f.request("PUT", path, a.Access, body, 200)
	entered, release := make(chan struct{}), make(chan struct{})
	f.push.BeforeRespond = func() { close(entered); <-release }
	f.push.Status.Store(410)
	done := make(chan struct{})
	go func() {
		defer close(done)
		f.request("POST", path+"/test", a.Access, map[string]string{"installation_secret": body["installation_secret"].(string), "message_id": uuid.NewString()}, 200)
	}()
	<-entered
	body["token"] = strings.Repeat("78", 32)
	f.request("PUT", path, a.Access, body, 200)
	close(release)
	<-done
	if f.count("SELECT COUNT(*) FROM devices WHERE id=?", id) != 1 {
		t.Fatal("fresh token deleted by old rejection")
	}
}
func TestReminderActivityLookupUsesIndex(t *testing.T) {
	f := setup(t)
	rows, err := f.db.Query(`EXPLAIN QUERY PLAN SELECT COALESCE(SUM(json_extract(data,'$.amount')),0) FROM records WHERE user_id=? AND kind='activity' AND deleted=0 AND json_extract(data,'$.habit_id')=? AND unixepoch(json_extract(data,'$.timestamp'))>=? AND unixepoch(json_extract(data,'$.timestamp'))<?`, "user", "habit", 0, 100)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	indexed := false
	for rows.Next() {
		var a, b, c int
		var detail string
		if err = rows.Scan(&a, &b, &c, &detail); err != nil {
			t.Fatal(err)
		}
		indexed = indexed || strings.Contains(detail, "activity_day")
	}
	if !indexed {
		t.Fatal("reminder quantity query does not use activity index")
	}
}
