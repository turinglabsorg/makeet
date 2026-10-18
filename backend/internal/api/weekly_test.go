package api_test

import (
	"bytes"
	"encoding/json"
	"github.com/google/uuid"
	"github.com/turinglabsorg/makeet/backend/internal/api"
	"testing"
)

func withWeekdays(t *testing.T, record api.Record, mask any) api.Record {
	t.Helper()
	var data map[string]any
	if err := json.Unmarshal(record.Data, &data); err != nil {
		t.Fatal(err)
	}
	data["weekday_mask"] = mask
	record.Data, _ = json.Marshal(data)
	return record
}

func TestWeeklyHabitSyncPreservesLegacyRetriesAndRejectsScheduleLoss(t *testing.T) {
	f := setup(t)
	user := f.login("google", "weekly")
	other := f.login("google", "other")
	id := uuid.NewString()
	first := api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{habit(id, 0)}}
	original := f.request("POST", "/v1/sync", user.Access, first, 200)
	retry := first
	retry.Changes = []api.Record{withWeekdays(t, habit(id, 0), 127)}
	if !bytes.Equal(bytes.TrimSpace(f.request("POST", "/v1/sync", user.Access, retry, 200)), bytes.TrimSpace(original)) {
		t.Fatal("legacy pending retry changed")
	}
	weekly := f.sync(user, 0, []api.Record{withWeekdays(t, habit(id, 1), 11)})
	var data map[string]any
	json.Unmarshal(weekly.Applied[0].Data, &data)
	if data["weekday_mask"] != float64(11) {
		t.Fatal("weekdays were not retained")
	}
	f.request("POST", "/v1/sync", user.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{habit(id, 2)}}, 409)
	if len(f.sync(other, 0, nil).Changes) != 0 {
		t.Fatal("calendar schedule crossed account")
	}
	daily := f.sync(user, weekly.Cursor, []api.Record{withWeekdays(t, habit(id, 2), 127)})
	if daily.Applied[0].Revision != 3 {
		t.Fatal("explicit return to daily failed")
	}
	var current map[string]any
	json.Unmarshal(daily.Applied[0].Data, &current)
	if _, exists := current["weekday_mask"]; exists {
		t.Fatal("daily wire format must remain canonical for legacy retries")
	}
}

func TestWeeklyHabitSyncValidatesMaskAtomically(t *testing.T) {
	f := setup(t)
	user := f.login("google", "validation")
	for _, value := range []any{0, -1, 128, 1.5, "mon"} {
		f.request("POST", "/v1/sync", user.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{habit(uuid.NewString(), 0), withWeekdays(t, habit(uuid.NewString(), 0), value)}}, 400)
	}
	if len(f.sync(user, 0, nil).Changes) != 0 {
		t.Fatal("invalid batch partially changed records")
	}
}
