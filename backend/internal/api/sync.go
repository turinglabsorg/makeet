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
			if strings.TrimSpace(data.Name) == "" {
				fail(w, 400, "invalid_record")
				return
			}
			change.Data, _ = json.Marshal(data)
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
		if current.Revision != change.Revision {
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
	for _, kind := range []string{"habit", "activity"} {
		for _, change := range req.Changes {
			if change.Kind == kind {
				ordered = append(ordered, change)
			}
		}
	}
	for _, change := range ordered {
		if change.Kind == "activity" && !change.Deleted {
			var a activityData
			json.Unmarshal(change.Data, &a)
			var exists int
			err = tx.QueryRowContext(r.Context(), "SELECT 1 FROM records WHERE user_id=? AND kind='habit' AND id=? AND deleted=0", p.UserID, a.HabitID).Scan(&exists)
			if errors.Is(err, sql.ErrNoRows) {
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
		result.Applied = append(result.Applied, change)
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
