package api_test

import (
	"bytes"
	"encoding/json"
	"github.com/google/uuid"
	"github.com/turinglabsorg/makeet/backend/internal/api"
	"strings"
	"testing"
)

func TestHabitDeletionCascadesRedactsHistoryAndCannotBeResurrected(t *testing.T) {
	f := setup(t)
	a := f.login("google", "delete")
	b := f.login("google", "keep")
	hid, aid := uuid.NewString(), uuid.NewString()
	original := api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{habit(hid, 0), activity(aid, hid)}}
	f.request("POST", "/v1/sync", a.Access, original, 200)
	f.sync(b, 0, []api.Record{habit(hid, 0), activity(aid, hid)})
	removed := api.Record{Kind: "habit", ID: hid, Revision: 1, Deleted: true, Data: json.RawMessage(`{}`)}
	request := api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{removed}}
	result := f.request("POST", "/v1/sync", a.Access, request, 200)
	replay := f.request("POST", "/v1/sync", a.Access, request, 200)
	if !bytes.Equal(bytes.TrimSpace(result), bytes.TrimSpace(replay)) {
		t.Fatal("delete retry changed")
	}
	var count int
	if err := f.db.QueryRow("SELECT count(*) FROM records WHERE user_id=? AND deleted=0", a.User.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("live records remained", err, count)
	}
	if err := f.db.QueryRow("SELECT count(*) FROM changes WHERE user_id=? AND (data!='{}' OR deleted=0)", a.User.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("deleted payload remained in sync history", err, count)
	}
	cached := f.request("POST", "/v1/sync", a.Access, original, 200)
	if bytes.Contains(cached, []byte("Water")) || bytes.Contains(cached, []byte("glasses")) {
		t.Fatal("cached retry leaked removed payload")
	}
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{habit(hid, 2)}}, 409)
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{activity(uuid.NewString(), hid)}}, 409)
	other := f.sync(b, 0, nil)
	if len(other.Changes) != 2 || other.Changes[0].Deleted || other.Changes[1].Deleted {
		t.Fatal("another account was affected")
	}
	for _, query := range []string{
		"EXPLAIN QUERY PLAN SELECT id,revision FROM records WHERE user_id=? AND kind='activity' AND deleted=0 AND json_extract(data,'$.habit_id')=?",
		"EXPLAIN QUERY PLAN UPDATE changes SET data='{}',deleted=1 WHERE user_id=? AND kind='activity' AND id=?",
	} {
		rows, err := f.db.Query(query, a.User.ID, hid)
		if err != nil {
			t.Fatal(err)
		}
		var plan string
		for rows.Next() {
			var x, y, z int
			var detail string
			if err = rows.Scan(&x, &y, &z, &detail); err != nil {
				t.Fatal(err)
			}
			plan += detail
		}
		rows.Close()
		if !strings.Contains(plan, "INDEX") {
			t.Fatal("deletion must use an account-scoped index", plan)
		}
	}
}

func TestDeletionAndLiveChildInSameBatchRollBack(t *testing.T) {
	f := setup(t)
	user := f.login("google", "atomic-delete")
	hid := uuid.NewString()
	f.sync(user, 0, []api.Record{habit(hid, 0)})
	f.request("POST", "/v1/sync", user.Access, api.SyncRequest{MutationID: uuid.NewString(), Changes: []api.Record{
		{Kind: "habit", ID: hid, Revision: 1, Deleted: true, Data: json.RawMessage(`{}`)}, activity(uuid.NewString(), hid),
	}}, 400)
	changes := f.sync(user, 0, nil).Changes
	if len(changes) != 1 || changes[0].Deleted {
		t.Fatal("rejected batch deleted the habit")
	}
}
