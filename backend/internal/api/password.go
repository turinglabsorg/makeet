package api

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"net/mail"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"golang.org/x/crypto/argon2"
)

type PasswordMailer interface {
	SendCode(context.Context, string, string, string, string) error
}

type passwordRequest struct {
	Username string `json:"username"`
	Email    string `json:"email"`
	Password string `json:"password"`
	Language string `json:"language"`
}

var usernamePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{2,31}$`)

func validPassword(value string) bool {
	return utf8.ValidString(value) && utf8.RuneCountInString(value) >= 15 && utf8.RuneCountInString(value) <= 128 && len(value) <= 512
}
func normalizedEmail(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	parsed, err := mail.ParseAddress(value)
	if err != nil || parsed.Address != value || len(value) > 254 || !strings.Contains(value, ".") {
		return ""
	}
	return value
}
func passwordHash(value string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key := argon2.IDKey([]byte(value), salt, 3, 64*1024, 2, 32)
	return "argon2id$v=19$m=65536,t=3,p=2$" + base64.RawStdEncoding.EncodeToString(salt) + "$" + base64.RawStdEncoding.EncodeToString(key), nil
}
func passwordMatches(value, encoded string) bool {
	parts := strings.Split(encoded, "$")
	salt := make([]byte, 16)
	expected := make([]byte, 32)
	valid := len(parts) == 5 && parts[0] == "argon2id" && parts[1] == "v=19" && parts[2] == "m=65536,t=3,p=2"
	if valid {
		var err error
		salt, err = base64.RawStdEncoding.DecodeString(parts[3])
		valid = err == nil && len(salt) == 16
		expected, err = base64.RawStdEncoding.DecodeString(parts[4])
		valid = valid && err == nil && len(expected) == 32
	}
	if !valid {
		salt = make([]byte, 16)
		expected = make([]byte, 32)
	}
	key := argon2.IDKey([]byte(value), salt, 3, 64*1024, 2, 32)
	return subtle.ConstantTimeCompare(key, expected) == 1 && valid
}
func (s *Server) passwordAvailable(w http.ResponseWriter, sending ...bool) bool {
	if s.cfg.Mailer == nil {
		fail(w, 503, "password_not_configured")
		return false
	}
	select {
	case s.passwordSlots <- struct{}{}:
		if len(sending) > 0 && sending[0] {
			select {
			case s.mailSlots <- struct{}{}:
			default:
				<-s.passwordSlots
				w.Header().Set("Retry-After", "5")
				fail(w, 429, "rate_limited")
				return false
			}
		}
		return true
	default:
		w.Header().Set("Retry-After", "5")
		fail(w, 429, "rate_limited")
		return false
	}
}
func (s *Server) passwordRegister(w http.ResponseWriter, r *http.Request) {
	s.passwordStart(w, r, "register", "")
}
func (s *Server) passwordEnroll(w http.ResponseWriter, r *http.Request, p principal) {
	s.passwordStart(w, r, "enroll", p.UserID)
}
func (s *Server) passwordStart(w http.ResponseWriter, r *http.Request, kind, userID string) {
	if !s.passwordAvailable(w, true) {
		return
	}
	queued := false
	defer func() {
		<-s.passwordSlots
		if !queued {
			<-s.mailSlots
		}
	}()
	var req passwordRequest
	if !decode(w, r, &req) {
		return
	}
	req.Username = strings.ToLower(strings.TrimSpace(req.Username))
	req.Email = normalizedEmail(req.Email)
	if !usernamePattern.MatchString(req.Username) || req.Email == "" || !validPassword(req.Password) {
		fail(w, 400, "invalid_credentials_format")
		return
	}
	encoded, err := passwordHash(req.Password)
	if err != nil {
		internal(w, err)
		return
	}
	queued = s.createPasswordRequest(w, r, kind, userID, req, encoded, 0)
}
func (s *Server) passwordRecover(w http.ResponseWriter, r *http.Request) {
	if !s.passwordAvailable(w, true) {
		return
	}
	queued := false
	defer func() {
		<-s.passwordSlots
		if !queued {
			<-s.mailSlots
		}
	}()
	var req struct {
		Identifier string `json:"identifier"`
		Language   string `json:"language"`
	}
	if !decode(w, r, &req) {
		return
	}
	identifier := strings.ToLower(strings.TrimSpace(req.Identifier))
	if len(identifier) < 3 || len(identifier) > 254 {
		fail(w, 400, "invalid_credentials_format")
		return
	}
	var userID string
	var version int
	out := passwordRequest{Language: req.Language, Email: normalizedEmail(identifier)}
	err := s.db.QueryRowContext(r.Context(), "SELECT user_id,username,email,version FROM password_credentials WHERE username=? OR email=?", identifier, identifier).Scan(&userID, &out.Username, &out.Email, &version)
	if errors.Is(err, sql.ErrNoRows) {
		respond(w, 202, map[string]string{"request_id": uuid.NewString()})
		return
	}
	if err != nil {
		internal(w, err)
		return
	}
	queued = s.createPasswordRequest(w, r, "recover", userID, out, "", version)
}
func (s *Server) createPasswordRequest(w http.ResponseWriter, r *http.Request, kind, userID string, req passwordRequest, encoded string, version int) bool {
	id := uuid.NewString()
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w, err)
		return false
	}
	defer tx.Rollback()
	now := s.cfg.Clock().Unix()
	if _, err = tx.ExecContext(r.Context(), "DELETE FROM password_requests WHERE expires_at<=?", now); err != nil {
		internal(w, err)
		return false
	}
	var count int
	if err = tx.QueryRowContext(r.Context(), "SELECT COUNT(*) FROM password_requests").Scan(&count); err != nil {
		internal(w, err)
		return false
	}
	if count >= 10000 {
		fail(w, 429, "rate_limited")
		return false
	}
	if userID != "" {
		if err = tx.QueryRowContext(r.Context(), "SELECT COUNT(*) FROM password_requests WHERE user_id=? AND created_at>?", userID, now-15*60).Scan(&count); err != nil {
			internal(w, err)
			return false
		}
		if count >= 3 {
			respond(w, 202, map[string]string{"request_id": id})
			return false
		}
	}
	if kind != "recover" {
		err = tx.QueryRowContext(r.Context(), "SELECT COUNT(*) FROM password_credentials WHERE username=? OR email=? OR user_id=?", req.Username, req.Email, userID).Scan(&count)
		if err != nil {
			internal(w, err)
			return false
		}
		if count > 0 {
			respond(w, 202, map[string]string{"request_id": id})
			return false
		}
	}
	if err = tx.QueryRowContext(r.Context(), "SELECT COUNT(*) FROM password_requests WHERE email=? AND created_at>?", req.Email, now-15*60).Scan(&count); err != nil {
		internal(w, err)
		return false
	}
	if count >= 3 {
		respond(w, 202, map[string]string{"request_id": id})
		return false
	}
	number, err := rand.Int(rand.Reader, big.NewInt(100000000))
	if err != nil {
		internal(w, err)
		return false
	}
	code := fmt.Sprintf("%08d", number.Int64())
	var owner any
	if userID != "" {
		owner = userID
	}
	_, err = tx.ExecContext(r.Context(), "INSERT INTO password_requests(id,user_id,kind,username,email,password_hash,credential_version,code_hash,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?,?,?)", id, owner, kind, req.Username, req.Email, encoded, version, hash(id+":"+code), now, now+15*60)
	if err != nil {
		internal(w, err)
		return false
	}
	if err = tx.Commit(); err != nil {
		internal(w, err)
		return false
	}
	go func() {
		defer func() { <-s.mailSlots }()
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if s.cfg.Mailer.SendCode(ctx, req.Email, code, kind, req.Language) != nil {
			cleanup, stop := context.WithTimeout(context.Background(), 3*time.Second)
			defer stop()
			s.db.ExecContext(cleanup, "DELETE FROM password_requests WHERE id=?", id)
		}
	}()
	respond(w, 202, map[string]string{"request_id": id})
	return true
}
func (s *Server) passwordLogin(w http.ResponseWriter, r *http.Request) {
	if !s.passwordAvailable(w) {
		return
	}
	defer func() { <-s.passwordSlots }()
	var req struct {
		Identifier string `json:"identifier"`
		Password   string `json:"password"`
	}
	if !decode(w, r, &req) {
		return
	}
	identifier := strings.ToLower(strings.TrimSpace(req.Identifier))
	if len(identifier) > 254 || len(identifier) < 3 || len(req.Password) > 512 {
		fail(w, 401, "invalid_credentials")
		return
	}
	now := s.cfg.Clock().Unix()
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w, err)
		return
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(r.Context(), "DELETE FROM password_attempts WHERE reset_at<=?", now); err != nil {
		internal(w, err)
		return
	}
	var total int
	if err = tx.QueryRowContext(r.Context(), "SELECT COUNT(*) FROM password_attempts").Scan(&total); err != nil {
		internal(w, err)
		return
	}
	if total >= 10000 {
		fail(w, 429, "rate_limited")
		return
	}
	_, err = tx.ExecContext(r.Context(), "INSERT INTO password_attempts VALUES(?,1,?) ON CONFLICT(identifier_hash) DO UPDATE SET failures=failures+1", hash(identifier), now+15*60)
	if err != nil {
		internal(w, err)
		return
	}
	var attempts int
	if err = tx.QueryRowContext(r.Context(), "SELECT failures FROM password_attempts WHERE identifier_hash=?", hash(identifier)).Scan(&attempts); err != nil {
		internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		internal(w, err)
		return
	}
	if attempts > 10 {
		w.Header().Set("Retry-After", "900")
		fail(w, 429, "rate_limited")
		return
	}
	var encoded, userID string
	var version int
	err = s.db.QueryRowContext(r.Context(), "SELECT user_id,password_hash,version FROM password_credentials WHERE username=? OR email=?", identifier, identifier).Scan(&userID, &encoded, &version)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		internal(w, err)
		return
	}
	if !passwordMatches(req.Password, encoded) {
		fail(w, 401, "invalid_credentials")
		return
	}
	tx, err = s.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w, err)
		return
	}
	defer tx.Rollback()
	u := user{ID: userID}
	if err = tx.QueryRowContext(r.Context(), "SELECT u.email FROM users u JOIN password_credentials c ON c.user_id=u.id WHERE c.user_id=? AND c.version=? AND c.password_hash=?", userID, version, encoded).Scan(&u.Email); err != nil {
		fail(w, 401, "invalid_credentials")
		return
	}
	result, err := s.issue(r.Context(), tx, u, "")
	if err != nil {
		internal(w, err)
		return
	}
	if _, err = tx.ExecContext(r.Context(), "DELETE FROM password_attempts WHERE identifier_hash=?", hash(identifier)); err != nil {
		internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		internal(w, err)
		return
	}
	respond(w, 200, result)
}
func (s *Server) passwordConfirm(w http.ResponseWriter, r *http.Request) { s.finishPassword(w, r, "") }
func (s *Server) passwordEnrollConfirm(w http.ResponseWriter, r *http.Request, p principal) {
	s.finishPassword(w, r, p.UserID)
}
func (s *Server) finishPassword(w http.ResponseWriter, r *http.Request, owner string) {
	if !s.passwordAvailable(w) {
		return
	}
	defer func() { <-s.passwordSlots }()
	var req struct {
		RequestID string `json:"request_id"`
		Code      string `json:"code"`
		Password  string `json:"password"`
	}
	if !decode(w, r, &req) {
		return
	}
	if _, err := uuid.Parse(req.RequestID); err != nil || len(req.Code) != 8 || len(req.Password) > 512 {
		fail(w, 400, "invalid_verification")
		return
	}
	encoded := ""
	if req.Password != "" {
		if !validPassword(req.Password) {
			fail(w, 400, "invalid_credentials_format")
			return
		}
		var err error
		encoded, err = passwordHash(req.Password)
		if err != nil {
			internal(w, err)
			return
		}
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w, err)
		return
	}
	defer tx.Rollback()
	var userID sql.NullString
	var kind, username, email, stored, proof string
	var version, attempts int
	err = tx.QueryRowContext(r.Context(), "SELECT user_id,kind,username,email,password_hash,credential_version,code_hash,attempts FROM password_requests WHERE id=? AND expires_at>?", req.RequestID, s.cfg.Clock().Unix()).Scan(&userID, &kind, &username, &email, &stored, &version, &proof, &attempts)
	if err != nil || attempts >= 10 || (kind == "enroll" && (owner == "" || owner != userID.String)) || (kind != "enroll" && owner != "") {
		fail(w, 400, "invalid_verification")
		return
	}
	if subtle.ConstantTimeCompare([]byte(hash(req.RequestID+":"+req.Code)), []byte(proof)) != 1 {
		if _, err = tx.ExecContext(r.Context(), "UPDATE password_requests SET attempts=attempts+1 WHERE id=?", req.RequestID); err != nil {
			internal(w, err)
			return
		}
		if err = tx.Commit(); err != nil {
			internal(w, err)
			return
		}
		fail(w, 400, "invalid_verification")
		return
	}
	if kind == "recover" {
		if encoded == "" {
			fail(w, 400, "invalid_credentials_format")
			return
		}
		res, err := tx.ExecContext(r.Context(), "UPDATE password_credentials SET password_hash=?,version=version+1 WHERE user_id=? AND version=?", encoded, userID.String, version)
		if err != nil {
			internal(w, err)
			return
		}
		n, _ := res.RowsAffected()
		if n != 1 {
			fail(w, 400, "invalid_verification")
			return
		}
		if _, err = tx.ExecContext(r.Context(), "DELETE FROM devices WHERE user_id=?", userID.String); err != nil {
			internal(w, err)
			return
		}
		if _, err = tx.ExecContext(r.Context(), "UPDATE sessions SET revoked=1 WHERE user_id=?", userID.String); err != nil {
			internal(w, err)
			return
		}
	} else {
		var count int
		if err = tx.QueryRowContext(r.Context(), "SELECT COUNT(*) FROM password_credentials WHERE username=? OR email=? OR user_id=?", username, email, userID.String).Scan(&count); err != nil {
			internal(w, err)
			return
		}
		if count > 0 {
			fail(w, 409, "credentials_unavailable")
			return
		}
		if kind == "register" {
			userID = sql.NullString{String: uuid.NewString(), Valid: true}
			if _, err = tx.ExecContext(r.Context(), "INSERT INTO users VALUES(?,?,?)", userID.String, email, s.cfg.Clock().Unix()); err != nil {
				internal(w, err)
				return
			}
		}
		if _, err = tx.ExecContext(r.Context(), "INSERT INTO password_credentials(user_id,username,email,password_hash) VALUES(?,?,?,?)", userID.String, username, email, stored); err != nil {
			internal(w, err)
			return
		}
	}
	if _, err = tx.ExecContext(r.Context(), "DELETE FROM password_requests WHERE id=? OR user_id=? OR (email=? AND kind='register')", req.RequestID, userID.String, email); err != nil {
		internal(w, err)
		return
	}
	if _, err = tx.ExecContext(r.Context(), "DELETE FROM password_attempts WHERE identifier_hash IN (?,?)", hash(username), hash(email)); err != nil {
		internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		internal(w, err)
		return
	}
	respond(w, 200, map[string]bool{"confirmed": true})
}
func (s *Server) passwordStatus(w http.ResponseWriter, r *http.Request, p principal) {
	var username, email string
	err := s.db.QueryRowContext(r.Context(), "SELECT username,email FROM password_credentials WHERE user_id=?", p.UserID).Scan(&username, &email)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		internal(w, err)
		return
	}
	respond(w, 200, map[string]any{"enabled": username != "", "username": username, "email": email})
}
