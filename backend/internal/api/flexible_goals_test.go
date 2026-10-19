package api_test

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/turinglabsorg/makeet/backend/internal/api"
)

func changeData(t *testing.T, record api.Record, values map[string]any) api.Record {
	t.Helper()
	var data map[string]any
	if err := json.Unmarshal(record.Data, &data); err != nil {
		t.Fatal(err)
	}
	for key, value := range values {
		data[key] = value
	}
	record.Data, _ = json.Marshal(data)
	return record
}

func TestZeroAndSignedGoalsRoundTripRetryExportAndRemainAccountPrivate(t *testing.T) {
	f := setup(t)
	a := f.login("google", "signed")
	b := f.login("google", "other")
	h := changeData(t, habit(uuid.NewString(), 0), map[string]any{"goal": "at_most", "target": 0, "allows_negative": true})
	zero := changeData(t, activity(uuid.NewString(), h.ID), map[string]any{"amount": 0})
	negative := changeData(t, activity(uuid.NewString(), h.ID), map[string]any{"amount": -2.5})
	req := api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{h, zero, negative}}
	first := f.request("POST", "/v1/sync", a.Access, req, 200)
	if strings.TrimSpace(string(first)) != strings.TrimSpace(string(f.request("POST", "/v1/sync", a.Access, req, 200))) {
		t.Fatal("retry changed response")
	}
	var result api.SyncResponse
	json.Unmarshal(first, &result)
	if len(result.Applied) != 3 {
		t.Fatal("signed records missing")
	}
	pull := f.sync(a, 0, nil)
	if len(pull.Changes) != 3 {
		t.Fatal("second device did not receive signed records")
	}
	if len(f.sync(b, 0, nil).Changes) != 0 {
		t.Fatal("account data leaked")
	}
	export := string(f.request("GET", "/v1/me/export", a.Access, nil, 200))
	for _, value := range []string{`"goal":"at_most"`, `"target":0`, `"amount":0`, `"amount":-2.5`} {
		if !strings.Contains(export, value) {
			t.Fatalf("export lost %s", value)
		}
	}
	legacy := f.requestProtocol("POST", "/v1/sync", a.Access, api.SyncRequest{}, 409, "")
	if !strings.Contains(string(legacy), "app_update_required") {
		t.Fatal("legacy client received incompatible records")
	}
	f.requestProtocol("POST", "/v1/sync", b.Access, api.SyncRequest{}, 200, "")
	bad := changeData(t, habit(uuid.NewString(), 0), map[string]any{"goal": "at_least", "target": 0})
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{bad}}, 400)
	bad = changeData(t, bad, map[string]any{"goal": "at_most", "target": -1})
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{bad}}, 400)
}

func TestLegacyCannotIntroduceOrOverwriteUnsupportedGoalsAndQueryUsesAccountIndex(t *testing.T) {
	f := setup(t)
	s := f.login("google", "legacy")
	h := changeData(t, habit(uuid.NewString(), 0), map[string]any{"goal": "at_most", "target": 0})
	req := api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{h}}
	f.requestProtocol("POST", "/v1/sync", s.Access, req, 409, "")
	if len(f.sync(s, 0, nil).Changes) != 0 {
		t.Fatal("legacy request partially applied")
	}
	f.sync(s, 0, []api.Record{h})
	old := habit(h.ID, 1)
	f.requestProtocol("POST", "/v1/sync", s.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{old}}, 409, "")
	result := f.sync(s, 0, nil)
	if !strings.Contains(string(result.Changes[0].Data), `"at_most"`) {
		t.Fatal("legacy edit overwrote goal")
	}
	rows, err := f.db.Query(`EXPLAIN QUERY PLAN SELECT 1 FROM records WHERE user_id=? AND deleted=0 AND ((kind='habit' AND (COALESCE(json_extract(data,'$.goal'),'at_least')='at_most' OR COALESCE(json_extract(data,'$.allows_negative'),0)=1)) OR (kind='activity' AND json_extract(data,'$.amount')<=0)) LIMIT 1`, s.User.ID)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var plan strings.Builder
	for rows.Next() {
		var id, parent, unused int
		var detail string
		if err = rows.Scan(&id, &parent, &unused, &detail); err != nil {
			t.Fatal(err)
		}
		plan.WriteString(detail)
	}
	if !strings.Contains(plan.String(), "SEARCH records USING") || strings.Contains(plan.String(), "SCAN records") {
		t.Fatal(plan.String())
	}
}

func TestLegacyPendingBatchRetrySurvivesDefaultGoalFieldsAddedByUpdatedClient(t *testing.T) {
	f := setup(t)
	account := f.login("google", "upgrade")
	h := habit(uuid.NewString(), 0)
	req := api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{h}}
	first := f.requestProtocol("POST", "/v1/sync", account.Access, req, 200, "")
	req.Changes[0] = changeData(t, h, map[string]any{"goal": "at_least", "allows_negative": false})
	retry := f.request("POST", "/v1/sync", account.Access, req, 200)
	if strings.TrimSpace(string(first)) != strings.TrimSpace(string(retry)) {
		t.Fatal("upgraded default fields changed a pending batch retry")
	}
	if len(f.sync(account, 0, nil).Changes) != 1 {
		t.Fatal("upgraded retry duplicated records")
	}
}

func TestLimitRemindersRequireUnloggedScheduledDay(t *testing.T) {
	for _, tc := range []struct {
		name    string
		amount  *float64
		weekday int
		future  bool
		want    int32
	}{
		{name: "unconfirmed", weekday: 127, want: 1},
		{name: "confirmed zero", amount: number(0), weekday: 127},
		{name: "malus already logged", amount: number(3), weekday: 127},
		{name: "negative already logged", amount: number(-1), weekday: 127},
		{name: "rest day", weekday: 1},
		{name: "not started", weekday: 127, future: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := setup(t)
			f.now = time.Date(2026, 10, 25, 9, 2, 0, 0, time.UTC)
			account := f.login("google", "limit")
			body := deviceBody(strings.Repeat("12", 32))
			body["reminders_enabled"] = true
			f.request("PUT", "/v1/devices/"+uuid.NewString(), account.Access, body, 200)
			values := map[string]any{"goal": "at_most", "target": 0, "allows_negative": true, "weekday_mask": tc.weekday}
			if tc.future {
				values["created_at"] = f.now.AddDate(0, 0, 1)
			}
			h := changeData(t, habit(uuid.NewString(), 0), values)
			changes := []api.Record{h}
			if tc.amount != nil {
				changes = append(changes, changeData(t, activity(uuid.NewString(), h.ID), map[string]any{"amount": *tc.amount, "timestamp": f.now.Add(-time.Hour)}))
			}
			f.sync(account, 0, changes)
			f.api.TickPush(context.Background())
			if got := f.push.Calls.Load(); got != tc.want {
				t.Fatalf("got %d reminders, want %d", got, tc.want)
			}
		})
	}
}
func number(value float64) *float64 { return &value }
