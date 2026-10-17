package api

import (
	"context"
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

func (s *Server) sendMessage(ctx context.Context, id string) {
	if s.cfg.Push == nil {
		return
	}
	now := s.cfg.Clock().Unix()
	res, err := s.db.ExecContext(ctx, `UPDATE push_messages SET attempts=attempts+1,next_attempt=? WHERE id=? AND status='pending' AND next_attempt<=? AND EXISTS(SELECT 1 FROM devices d JOIN sessions s ON s.id=d.session_id WHERE d.id=push_messages.device_id AND d.user_id=push_messages.user_id AND s.user_id=d.user_id AND s.revoked=0 AND s.expires_at>?)`, now+60, id, now, now)
	if err != nil {
		return
	}
	claimed, _ := res.RowsAffected()
	if claimed != 1 {
		return
	}
	var userID, device, topic, environment, language, kind string
	var token []byte
	var created int64
	var attempts int
	err = s.db.QueryRowContext(ctx, `SELECT m.user_id,d.id,d.topic,d.environment,d.language,d.token,m.kind,m.created_at,m.attempts FROM push_messages m JOIN devices d ON d.id=m.device_id AND d.user_id=m.user_id WHERE m.id=?`, id).Scan(&userID, &device, &topic, &environment, &language, &token, &kind, &created, &attempts)
	if err != nil {
		return
	}
	if now-created > 600 || attempts > 5 {
		s.db.ExecContext(ctx, "UPDATE push_messages SET status='failed' WHERE id=?", id)
		return
	}
	if !s.cfg.Push.Available(topic, environment) {
		return
	}
	plain, err := s.cfg.Push.Open(userID, device, topic, token)
	if err != nil {
		s.db.ExecContext(ctx, "UPDATE push_messages SET status='failed' WHERE id=?", id)
		return
	}
	result, sendErr := s.cfg.Push.Send(ctx, topic, plain, id, notificationPayload(language, kind, id))
	if sendErr == nil && result.Accepted {
		s.db.ExecContext(ctx, "UPDATE push_messages SET status='accepted',accepted_at=? WHERE id=?", s.cfg.Clock().Unix(), id)
		return
	}
	if sendErr == nil && result.InvalidToken {
		// A rejected old token must not remove a registration refreshed during the request.
		s.db.ExecContext(ctx, "DELETE FROM devices WHERE id=? AND user_id=? AND token=?", device, userID, token)
		return
	}
	if attempts >= 5 || (sendErr == nil && !result.Retryable) {
		s.db.ExecContext(ctx, "UPDATE push_messages SET status='failed' WHERE id=?", id)
	} else {
		delay := int64(60 * attempts)
		s.db.ExecContext(ctx, "UPDATE push_messages SET next_attempt=? WHERE id=?", s.cfg.Clock().Unix()+delay, id)
	}
}

func (s *Server) TickPush(ctx context.Context) {
	if s.cfg.Push == nil {
		return
	}
	now := s.cfg.Clock()
	s.scheduleReminders(ctx, now)
	rows, err := s.db.QueryContext(ctx, "SELECT id FROM push_messages WHERE status='pending' AND next_attempt<=? ORDER BY next_attempt LIMIT 20", now.Unix())
	if err != nil {
		return
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()
	for _, id := range ids {
		if ctx.Err() != nil {
			return
		}
		s.sendMessage(ctx, id)
	}
	s.db.ExecContext(ctx, "DELETE FROM push_messages WHERE created_at<?", now.Add(-30*24*time.Hour).Unix())
}

func (s *Server) RunPush(ctx context.Context) {
	if s.cfg.Push == nil {
		return
	}
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		s.TickPush(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (s *Server) scheduleReminders(ctx context.Context, now time.Time) {
	rows, err := s.db.QueryContext(ctx, `SELECT d.id,d.user_id,d.time_zone,d.reminder_hour,d.reminder_minute,d.topic,d.environment FROM devices d JOIN sessions s ON s.id=d.session_id WHERE d.reminders_enabled=1 AND s.revoked=0 AND s.expires_at>? AND s.user_id=d.user_id`, now.Unix())
	if err != nil {
		return
	}
	type device struct {
		id, user, zone, topic, environment string
		hour, minute                       int
	}
	devices := []device{}
	for rows.Next() {
		var d device
		if rows.Scan(&d.id, &d.user, &d.zone, &d.hour, &d.minute, &d.topic, &d.environment) == nil {
			devices = append(devices, d)
		}
	}
	rows.Close()
	for _, d := range devices {
		if ctx.Err() != nil {
			return
		}
		if !s.cfg.Push.Available(d.topic, d.environment) {
			continue
		}
		zone, err := time.LoadLocation(d.zone)
		if err != nil {
			continue
		}
		local := now.In(zone)
		scheduled := time.Date(local.Year(), local.Month(), local.Day(), d.hour, d.minute, 0, 0, zone)
		if scheduled.Hour() != d.hour || scheduled.Minute() != d.minute || now.Before(scheduled) || now.Sub(scheduled) >= 15*time.Minute {
			continue
		}
		if !s.hasIncompleteHabit(ctx, d.user, now) {
			continue
		}
		s.db.ExecContext(ctx, "INSERT OR IGNORE INTO push_messages(id,device_id,user_id,kind,day,created_at,next_attempt) VALUES(?,?,?,'reminder',?,?,?)", uuid.NewString(), d.id, d.user, local.Format("2006-01-02"), now.Unix(), now.Unix())
	}
}

func (s *Server) hasIncompleteHabit(ctx context.Context, user string, now time.Time) bool {
	rows, err := s.db.QueryContext(ctx, "SELECT id,data FROM records WHERE user_id=? AND kind='habit' AND deleted=0", user)
	if err != nil {
		return false
	}
	type habit struct {
		id   string
		data habitData
	}
	habits := []habit{}
	for rows.Next() {
		var id, raw string
		if rows.Scan(&id, &raw) == nil {
			var data habitData
			if json.Unmarshal([]byte(raw), &data) == nil && !data.Archived {
				habits = append(habits, habit{id, data})
			}
		}
	}
	rows.Close()
	for _, h := range habits {
		zone, err := time.LoadLocation(h.data.TimeZoneID)
		if err != nil {
			continue
		}
		local := now.In(zone)
		start := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, zone)
		end := start.AddDate(0, 0, 1)
		var quantity float64
		err = s.db.QueryRowContext(ctx, `SELECT COALESCE(SUM(json_extract(data,'$.amount')),0) FROM records WHERE user_id=? AND kind='activity' AND deleted=0 AND json_extract(data,'$.habit_id')=? AND unixepoch(json_extract(data,'$.timestamp'))>=? AND unixepoch(json_extract(data,'$.timestamp'))<?`, user, h.id, start.Unix(), end.Unix()).Scan(&quantity)
		if err == nil && quantity < h.data.Target {
			return true
		}
	}
	return false
}
