package api

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/turinglabsorg/makeet/backend/internal/push"
)

type deviceRequest struct {
	InstallationSecret string `json:"installation_secret"`
	Token              string `json:"token"`
	Topic              string `json:"topic"`
	Environment        string `json:"environment"`
	Language           string `json:"language"`
	TimeZone           string `json:"time_zone"`
	RemindersEnabled   bool   `json:"reminders_enabled"`
	ReminderHour       int    `json:"reminder_hour"`
	ReminderMinute     int    `json:"reminder_minute"`
}

func installationValid(value string) bool {
	raw, err := base64.RawURLEncoding.DecodeString(value)
	return err == nil && len(raw) == 32
}

func deviceID(r *http.Request) (string, error) {
	id, err := uuid.Parse(r.PathValue("id"))
	return id.String(), err
}

func (s *Server) registerDevice(w http.ResponseWriter, r *http.Request, p principal) {
	var req deviceRequest
	if !decode(w, r, &req) {
		return
	}
	id, err := deviceID(r)
	_, zoneErr := time.LoadLocation(req.TimeZone)
	if err != nil || !installationValid(req.InstallationSecret) || !push.ValidToken(req.Token) || zoneErr != nil || req.ReminderHour < 0 || req.ReminderHour > 23 || req.ReminderMinute < 0 || req.ReminderMinute > 59 || !supportedLanguage(req.Language) {
		fail(w, 400, "invalid_device")
		return
	}
	if !s.cfg.Push.Available(req.Topic, req.Environment) {
		fail(w, 503, "push_not_configured")
		return
	}
	sealed, err := s.cfg.Push.Seal(p.UserID, id, req.Topic, strings.ToLower(req.Token))
	if err != nil {
		internal(w, err)
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w, err)
		return
	}
	defer tx.Rollback()
	var savedSecret string
	err = tx.QueryRowContext(r.Context(), "SELECT installation_hash FROM devices WHERE id=?", id).Scan(&savedSecret)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		internal(w, err)
		return
	}
	if err == nil && savedSecret != hash(req.InstallationSecret) {
		fail(w, 409, "installation_mismatch")
		return
	}
	var count int
	if err = tx.QueryRowContext(r.Context(), "SELECT COUNT(*) FROM devices WHERE user_id=? AND id<>?", p.UserID, id).Scan(&count); err != nil {
		internal(w, err)
		return
	}
	if count >= 20 {
		fail(w, 429, "device_limit")
		return
	}
	// A refreshed installation may reuse the same APNs token; it must stop receiving the old account's messages.
	if _, err = tx.ExecContext(r.Context(), "DELETE FROM devices WHERE token_hash=? AND topic=? AND environment=? AND id<>?", hash(strings.ToLower(req.Token)), req.Topic, req.Environment, id); err != nil {
		internal(w, err)
		return
	}
	if _, err = tx.ExecContext(r.Context(), "DELETE FROM push_messages WHERE device_id=? AND user_id<>?", id, p.UserID); err != nil {
		internal(w, err)
		return
	}
	_, err = tx.ExecContext(r.Context(), `INSERT INTO devices VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET user_id=excluded.user_id,session_id=excluded.session_id,token=excluded.token,token_hash=excluded.token_hash,topic=excluded.topic,environment=excluded.environment,language=excluded.language,time_zone=excluded.time_zone,reminders_enabled=excluded.reminders_enabled,reminder_hour=excluded.reminder_hour,reminder_minute=excluded.reminder_minute,updated_at=excluded.updated_at`, id, p.UserID, p.SessionID, hash(req.InstallationSecret), sealed, hash(strings.ToLower(req.Token)), req.Topic, req.Environment, req.Language, req.TimeZone, req.RemindersEnabled, req.ReminderHour, req.ReminderMinute, s.cfg.Clock().Unix())
	if err != nil {
		internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		internal(w, err)
		return
	}
	var accepted, confirmed int64
	if err = s.db.QueryRowContext(r.Context(), "SELECT COALESCE(MAX(accepted_at),0),COALESCE(MAX(confirmed_at),0) FROM push_messages WHERE device_id=? AND user_id=?", id, p.UserID).Scan(&accepted, &confirmed); err != nil {
		internal(w, err)
		return
	}
	respond(w, 200, map[string]any{"registered": true, "accepted_at": accepted, "confirmed_at": confirmed})
}

func (s *Server) ownedDevice(ctx context.Context, id string, p principal, secret string) bool {
	if !installationValid(secret) {
		return false
	}
	var exists int
	return s.db.QueryRowContext(ctx, "SELECT 1 FROM devices WHERE id=? AND user_id=? AND session_id=? AND installation_hash=?", id, p.UserID, p.SessionID, hash(secret)).Scan(&exists) == nil
}

func (s *Server) removeDevice(w http.ResponseWriter, r *http.Request, p principal) {
	var req struct {
		InstallationSecret string `json:"installation_secret"`
	}
	if !decode(w, r, &req) {
		return
	}
	id, err := deviceID(r)
	if err != nil || !s.ownedDevice(r.Context(), id, p, req.InstallationSecret) {
		fail(w, 404, "device_not_found")
		return
	}
	if _, err = s.db.ExecContext(r.Context(), "DELETE FROM devices WHERE id=? AND user_id=? AND session_id=? AND installation_hash=?", id, p.UserID, p.SessionID, hash(req.InstallationSecret)); err != nil {
		internal(w, err)
		return
	}
	w.WriteHeader(204)
}

func (s *Server) testPush(w http.ResponseWriter, r *http.Request, p principal) {
	var req struct {
		InstallationSecret string `json:"installation_secret"`
		MessageID          string `json:"message_id"`
	}
	if !decode(w, r, &req) {
		return
	}
	id, err := deviceID(r)
	message, messageErr := uuid.Parse(req.MessageID)
	if err != nil || messageErr != nil {
		fail(w, 400, "invalid_device_request")
		return
	}
	if !s.ownedDevice(r.Context(), id, p, req.InstallationSecret) {
		fail(w, 404, "device_not_found")
		return
	}
	if s.cfg.Push == nil {
		fail(w, 503, "push_not_configured")
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w, err)
		return
	}
	defer tx.Rollback()
	var existingDevice, existingUser string
	err = tx.QueryRowContext(r.Context(), "SELECT device_id,user_id FROM push_messages WHERE id=?", message.String()).Scan(&existingDevice, &existingUser)
	if err == nil && (existingDevice != id || existingUser != p.UserID) {
		fail(w, 409, "message_id_reused")
		return
	}
	if errors.Is(err, sql.ErrNoRows) {
		var recent int
		if err = tx.QueryRowContext(r.Context(), "SELECT COUNT(*) FROM push_messages WHERE device_id=? AND kind='test' AND created_at>?", id, s.cfg.Clock().Add(-time.Minute).Unix()).Scan(&recent); err != nil {
			internal(w, err)
			return
		}
		if recent > 0 {
			w.Header().Set("Retry-After", "60")
			fail(w, 429, "push_rate_limited")
			return
		}
		if _, err = tx.ExecContext(r.Context(), "INSERT INTO push_messages(id,device_id,user_id,kind,created_at,next_attempt) VALUES(?,?,?,'test',?,?)", message.String(), id, p.UserID, s.cfg.Clock().Unix(), s.cfg.Clock().Unix()); err != nil {
			internal(w, err)
			return
		}
	} else if err != nil {
		internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		internal(w, err)
		return
	}
	s.sendMessage(r.Context(), message.String())
	var status string
	var confirmed int64
	if err = s.db.QueryRowContext(r.Context(), "SELECT status,confirmed_at FROM push_messages WHERE id=? AND device_id=? AND user_id=?", message.String(), id, p.UserID).Scan(&status, &confirmed); err != nil {
		fail(w, 503, "push_unavailable")
		return
	}
	respond(w, 200, map[string]any{"message_id": message.String(), "status": status, "confirmed_at": confirmed})
}

func (s *Server) confirmPush(w http.ResponseWriter, r *http.Request, p principal) {
	var req struct {
		InstallationSecret string `json:"installation_secret"`
		MessageID          string `json:"message_id"`
	}
	if !decode(w, r, &req) {
		return
	}
	id, err := deviceID(r)
	message, messageErr := uuid.Parse(req.MessageID)
	if err != nil || messageErr != nil || !s.ownedDevice(r.Context(), id, p, req.InstallationSecret) {
		fail(w, 404, "device_not_found")
		return
	}
	res, err := s.db.ExecContext(r.Context(), "UPDATE push_messages SET confirmed_at=? WHERE id=? AND device_id=? AND user_id=?", s.cfg.Clock().Unix(), message.String(), id, p.UserID)
	if err != nil {
		internal(w, err)
		return
	}
	n, _ := res.RowsAffected()
	if n != 1 {
		fail(w, 404, "message_not_found")
		return
	}
	w.WriteHeader(204)
}

func supportedLanguage(language string) bool {
	return language == "it" || language == "en" || language == "fr" || language == "de" || language == "es"
}

func notificationPayload(language, kind, id string) []byte {
	bodies := map[string][2]string{
		"it": {"Le notifiche Makeet sono collegate.", "Un piccolo passo, oggi. Apri Makeet per le tue abitudini."},
		"en": {"Makeet notifications are connected.", "One small step today. Open Makeet for your habits."},
		"fr": {"Les notifications Makeet sont connectées.", "Un petit pas aujourd’hui. Ouvrez Makeet pour vos habitudes."},
		"de": {"Makeet-Benachrichtigungen sind verbunden.", "Ein kleiner Schritt heute. Öffne Makeet für deine Gewohnheiten."},
		"es": {"Las notificaciones de Makeet están conectadas.", "Un pequeño paso hoy. Abre Makeet para tus hábitos."},
	}
	body := bodies[language]
	index := 0
	if kind == "reminder" {
		index = 1
	}
	payload, _ := json.Marshal(map[string]any{"aps": map[string]any{"alert": map[string]string{"title": "Makeet", "body": body[index]}, "sound": "default"}, "destination": "today", "notification_id": id})
	return payload
}
