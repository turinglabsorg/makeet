package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
)

type Record struct {
	Kind     string          `json:"kind"`
	ID       string          `json:"id"`
	Revision int64           `json:"revision"`
	Deleted  bool            `json:"deleted"`
	Data     json.RawMessage `json:"data"`
}
type SyncRequest struct {
	Cursor     int64    `json:"cursor"`
	MutationID string   `json:"mutation_id"`
	Changes    []Record `json:"changes"`
}
type SyncResponse struct {
	Cursor  int64    `json:"cursor"`
	HasMore bool     `json:"has_more"`
	Changes []Record `json:"changes"`
	Applied []Record `json:"applied"`
}
type habitData struct {
	Name            string    `json:"name"`
	Symbol          string    `json:"symbol"`
	ColorIndex      int       `json:"color_index"`
	Target          float64   `json:"target"`
	Step            float64   `json:"step"`
	Unit            string    `json:"unit"`
	CreatedAt       time.Time `json:"created_at"`
	TimeZoneID      string    `json:"time_zone_id"`
	PreferredHour   int       `json:"preferred_hour"`
	DurationMinutes int       `json:"duration_minutes"`
	Archived        bool      `json:"archived"`
	WeekdayMask     *int      `json:"weekday_mask,omitempty"`
}
type activityData struct {
	HabitID   string    `json:"habit_id"`
	Amount    float64   `json:"amount"`
	Timestamp time.Time `json:"timestamp"`
	Source    string    `json:"source"`
}

func strictData(data []byte, v any) error {
	d := json.NewDecoder(bytes.NewReader(data))
	d.DisallowUnknownFields()
	return d.Decode(v)
}
func validate(c Record) error {
	if _, err := uuid.Parse(c.ID); err != nil {
		return err
	}
	if c.Kind != "habit" && c.Kind != "activity" {
		return errors.New("invalid kind")
	}
	if c.Revision < 0 {
		return errors.New("invalid revision")
	}
	if c.Deleted {
		return nil
	}
	if c.Kind == "habit" {
		var h habitData
		if err := strictData(c.Data, &h); err != nil {
			return err
		}
		_, zoneErr := time.LoadLocation(h.TimeZoneID)
		if h.WeekdayMask != nil && (*h.WeekdayMask < 1 || *h.WeekdayMask > 127) {
			return errors.New("invalid weekdays")
		}
		if len(h.Name) < 1 || len(h.Name) > 200 || len(h.Symbol) > 80 || len(h.Unit) < 1 || len(h.Unit) > 50 || h.Target <= 0 || h.Step <= 0 || math.IsInf(h.Target, 0) || math.IsInf(h.Step, 0) || h.PreferredHour < 0 || h.PreferredHour > 23 || h.DurationMinutes < 5 || h.DurationMinutes > 240 || h.ColorIndex < 0 || h.ColorIndex > 3 || h.CreatedAt.IsZero() || zoneErr != nil {
			return errors.New("invalid habit")
		}
	} else {
		var a activityData
		if err := strictData(c.Data, &a); err != nil {
			return err
		}
		if _, err := uuid.Parse(a.HabitID); err != nil {
			return err
		}
		if a.Amount <= 0 || math.IsInf(a.Amount, 0) || a.Timestamp.IsZero() || len(a.Source) > 32 {
			return errors.New("invalid activity")
		}
	}
	return nil
}
func (s *Server) syncRecords(w http.ResponseWriter, r *http.Request, p principal) {
	entitlement, billingErr := s.entitlement(r.Context(), p.UserID)
	if billingErr != nil {
		internal(w, billingErr)
		return
	}
	if entitlement.Enabled && !entitlement.Active {
		fail(w, 403, "subscription_required")
		return
	}
	var req SyncRequest
	if !decode(w, r, &req) {
		return
	}
	if req.Cursor < 0 || len(req.Changes) > 100 {
		fail(w, 400, "invalid_sync_request")
		return
	}
	if len(req.Changes) > 0 {
		if _, err := uuid.Parse(req.MutationID); err != nil {
			fail(w, 400, "mutation_id_required")
			return
		}
	}
	if req.MutationID != "" {
		if id, err := uuid.Parse(req.MutationID); err == nil {
			req.MutationID = id.String()
		}
	}
	seen := map[string]bool{}
	weekdaysSpecified := map[string]bool{}
	for i := range req.Changes {
		change := &req.Changes[i]
		if id, err := uuid.Parse(change.ID); err == nil {
			change.ID = id.String()
		}
		if !change.Deleted && change.Kind == "activity" {
			var data activityData
			if strictData(change.Data, &data) == nil {
				if id, err := uuid.Parse(data.HabitID); err == nil {
					data.HabitID = id.String()
				}
				change.Data, _ = json.Marshal(data)
			}
		}
		key := change.Kind + change.ID
		if seen[key] || validate(*change) != nil {
			fail(w, 400, "invalid_record")
			return
		}
		seen[key] = true
		if !change.Deleted && change.Kind == "habit" {
			var data habitData
			json.Unmarshal(change.Data, &data)
			weekdaysSpecified[change.ID] = data.WeekdayMask != nil
			if data.WeekdayMask != nil && *data.WeekdayMask == 127 {
				data.WeekdayMask = nil
			}
			if strings.TrimSpace(data.Name) == "" {
				fail(w, 400, "invalid_record")
				return
			}
			change.Data, _ = json.Marshal(data)
		}
	}
	deletedParents := map[string]bool{}
	for _, change := range req.Changes {
		if change.Kind == "habit" && change.Deleted {
			deletedParents[change.ID] = true
		}
	}
	for _, change := range req.Changes {
		if change.Kind == "activity" && !change.Deleted {
			var data activityData
			json.Unmarshal(change.Data, &data)
			if deletedParents[data.HabitID] {
				fail(w, 400, "habit_not_found")
				return
			}
		}
	}
	body, _ := json.Marshal(req)
	digest := hash(string(body))
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w, err)
		return
	}
	defer tx.Rollback()
	if len(req.Changes) > 0 {
		var savedHash, savedResponse string
		err = tx.QueryRowContext(r.Context(), "SELECT request_hash,response FROM batches WHERE user_id=? AND id=?", p.UserID, req.MutationID).Scan(&savedHash, &savedResponse)
		if err == nil {
			if savedHash != digest {
				fail(w, 409, "mutation_id_reused")
				return
			}
			w.Header().Set("Content-Type", "application/json")
			w.Write([]byte(savedResponse))
			return
		}
		if !errors.Is(err, sql.ErrNoRows) {
			internal(w, err)
			return
		}
	}
	conflicts := []Record{}
	for _, change := range req.Changes {
		var current Record
		current.Kind = change.Kind
		current.ID = change.ID
		var data string
		err = tx.QueryRowContext(r.Context(), "SELECT revision,deleted,data FROM records WHERE user_id=? AND kind=? AND id=?", p.UserID, change.Kind, change.ID).Scan(&current.Revision, &current.Deleted, &data)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			internal(w, err)
			return
		}
		legacyScheduleConflict := false
		if change.Kind == "habit" && !change.Deleted && data != "" {
			var incoming, existing habitData
			json.Unmarshal(change.Data, &incoming)
			json.Unmarshal([]byte(data), &existing)
			legacyScheduleConflict = !weekdaysSpecified[change.ID] && existing.WeekdayMask != nil && *existing.WeekdayMask != 127
		}
		if current.Revision != change.Revision || legacyScheduleConflict || (current.Deleted && !change.Deleted) {
			current.Data = json.RawMessage(data)
			if len(current.Data) == 0 {
				current.Data = json.RawMessage(`{}`)
			}
			conflicts = append(conflicts, current)
		}
	}
	if len(conflicts) > 0 {
		respond(w, 409, map[string]any{"error": "revision_conflict", "conflicts": conflicts})
		return
	}
	result := SyncResponse{Cursor: req.Cursor, Changes: []Record{}, Applied: []Record{}}
	// Habits precede activities even when a client sends a mixed batch.
	ordered := []Record{}
	requested := map[string]bool{}
	for _, change := range req.Changes {
		requested[change.Kind+change.ID] = true
	}
	for _, kind := range []string{"habit", "activity"} {
		for _, change := range req.Changes {
			if change.Kind == kind {
				ordered = append(ordered, change)
			}
		}
	}
	for _, change := range req.Changes {
		if change.Kind != "habit" || !change.Deleted {
			continue
		}
		rows, queryErr := tx.QueryContext(r.Context(), "SELECT id,revision FROM records WHERE user_id=? AND kind='activity' AND deleted=0 AND json_extract(data,'$.habit_id')=?", p.UserID, change.ID)
		if queryErr != nil {
			internal(w, queryErr)
			return
		}
		for rows.Next() {
			var child Record
			child.Kind = "activity"
			child.Deleted = true
			if queryErr = rows.Scan(&child.ID, &child.Revision); queryErr != nil {
				rows.Close()
				internal(w, queryErr)
				return
			}
			if !seen[child.Kind+child.ID] {
				ordered = append(ordered, child)
				seen[child.Kind+child.ID] = true
			}
		}
		queryErr = rows.Err()
		rows.Close()
		if queryErr != nil {
			internal(w, queryErr)
			return
		}
	}
	for _, change := range ordered {
		if change.Kind == "activity" && !change.Deleted {
			var a activityData
			json.Unmarshal(change.Data, &a)
			var exists int
			err = tx.QueryRowContext(r.Context(), "SELECT 1 FROM records WHERE user_id=? AND kind='habit' AND id=? AND deleted=0", p.UserID, a.HabitID).Scan(&exists)
			if errors.Is(err, sql.ErrNoRows) {
				var parent Record
				parent.Kind = "habit"
				parent.ID = a.HabitID
				if tx.QueryRowContext(r.Context(), "SELECT revision FROM records WHERE user_id=? AND kind='habit' AND id=? AND deleted=1", p.UserID, a.HabitID).Scan(&parent.Revision) == nil {
					parent.Deleted = true
					parent.Data = json.RawMessage(`{}`)
					child := change
					child.Deleted = true
					child.Data = json.RawMessage(`{}`)
					respond(w, 409, map[string]any{"error": "revision_conflict", "conflicts": []Record{parent, child}})
					return
				}
				fail(w, 400, "habit_not_found")
				return
			}
			if err != nil {
				internal(w, err)
				return
			}
		}
		change.Revision++
		if change.Deleted {
			change.Data = json.RawMessage(`{}`)
		}
		_, err = tx.ExecContext(r.Context(), "INSERT INTO records VALUES(?,?,?,?,?,?) ON CONFLICT(user_id,kind,id) DO UPDATE SET revision=excluded.revision,deleted=excluded.deleted,data=excluded.data", p.UserID, change.Kind, change.ID, change.Revision, change.Deleted, string(change.Data))
		if err != nil {
			internal(w, err)
			return
		}
		_, err = tx.ExecContext(r.Context(), "INSERT INTO changes(user_id,kind,id,revision,deleted,data) VALUES(?,?,?,?,?,?)", p.UserID, change.Kind, change.ID, change.Revision, change.Deleted, string(change.Data))
		if err != nil {
			internal(w, err)
			return
		}
		if requested[change.Kind+change.ID] {
			result.Applied = append(result.Applied, change)
		}
	}
	if err = redactDeletedRecords(r, tx, p.UserID, ordered); err != nil {
		internal(w, err)
		return
	}
	rows, err := tx.QueryContext(r.Context(), "SELECT sequence,kind,id,revision,deleted,data FROM changes WHERE user_id=? AND sequence>? ORDER BY sequence LIMIT 201", p.UserID, req.Cursor)
	if err != nil {
		internal(w, err)
		return
	}
	for rows.Next() {
		var c Record
		var seq int64
		var data string
		if err = rows.Scan(&seq, &c.Kind, &c.ID, &c.Revision, &c.Deleted, &data); err != nil {
			rows.Close()
			internal(w, err)
			return
		}
		if len(result.Changes) == 200 {
			result.HasMore = true
			break
		}
		c.Data = json.RawMessage(data)
		result.Changes = append(result.Changes, c)
		result.Cursor = seq
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		internal(w, err)
		return
	}
	raw, err := json.Marshal(result)
	if err != nil {
		internal(w, err)
		return
	}
	if len(req.Changes) > 0 {
		_, err = tx.ExecContext(r.Context(), "INSERT INTO batches VALUES(?,?,?,?)", p.UserID, req.MutationID, digest, string(raw))
		if err != nil {
			internal(w, err)
			return
		}
	}
	if err = tx.Commit(); err != nil {
		internal(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintln(w, string(raw))
}

func redactDeletedRecords(r *http.Request, tx *sql.Tx, userID string, records []Record) error {
	removed := map[string]Record{}
	for _, record := range records {
		if !record.Deleted {
			continue
		}
		record.Revision++
		record.Data = json.RawMessage(`{}`)
		removed[record.Kind+record.ID] = record
		if _, err := tx.ExecContext(r.Context(), "UPDATE changes SET data='{}',deleted=1 WHERE user_id=? AND kind=? AND id=?", userID, record.Kind, record.ID); err != nil {
			return err
		}
	}
	if len(removed) == 0 {
		return nil
	}
	rows, err := tx.QueryContext(r.Context(), "SELECT id,response FROM batches WHERE user_id=?", userID)
	if err != nil {
		return err
	}
	type batch struct{ id, response string }
	var updates []batch
	for rows.Next() {
		var id, raw string
		if err = rows.Scan(&id, &raw); err != nil {
			rows.Close()
			return err
		}
		var response SyncResponse
		if err = json.Unmarshal([]byte(raw), &response); err != nil {
			rows.Close()
			return err
		}
		changed := false
		for _, collection := range [][]Record{response.Changes, response.Applied} {
			for index, old := range collection {
				if tombstone, ok := removed[old.Kind+old.ID]; ok {
					collection[index] = tombstone
					changed = true
				}
			}
		}
		if changed {
			value, marshalErr := json.Marshal(response)
			if marshalErr != nil {
				rows.Close()
				return marshalErr
			}
			updates = append(updates, batch{id, string(value)})
		}
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, update := range updates {
		if _, err = tx.ExecContext(r.Context(), "UPDATE batches SET response=? WHERE user_id=? AND id=?", update.response, userID, update.id); err != nil {
			return err
		}
	}
	return nil
}
