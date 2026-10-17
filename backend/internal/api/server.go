package api

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/turinglabsorg/makeet/backend/internal/apple"
	"github.com/turinglabsorg/makeet/backend/internal/identity"
	"github.com/turinglabsorg/makeet/backend/internal/push"
)

type Config struct {
	Providers  map[string]identity.Verifier
	Apple      *apple.Client
	Push       *push.Client
	Site       http.Handler
	Clock      func() time.Time
	TrustRelay bool
}
type Server struct {
	db     *sql.DB
	cfg    Config
	mu     sync.Mutex
	limits map[string]bucket
}
type bucket struct {
	start time.Time
	count int
}
type principal struct{ UserID, SessionID string }
type user struct {
	ID    string `json:"id"`
	Email string `json:"email"`
}
type tokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
	User         user   `json:"user"`
}

func New(db *sql.DB, cfg Config) *Server {
	if cfg.Clock == nil {
		cfg.Clock = time.Now
	}
	return &Server{db: db, cfg: cfg, limits: make(map[string]bucket)}
}
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		if s.db.PingContext(r.Context()) != nil {
			fail(w, 503, "unavailable")
			return
		}
		respond(w, 200, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /v1/config", func(w http.ResponseWriter, r *http.Request) {
		providers := []string{}
		for _, p := range []string{"apple", "google"} {
			if s.providerAvailable(p) {
				providers = append(providers, p)
			}
		}
		respond(w, 200, map[string]any{"providers": providers})
	})
	mux.HandleFunc("POST /v1/auth/challenges", s.challenge)
	mux.HandleFunc("POST /v1/auth/exchange", s.exchange)
	mux.HandleFunc("POST /v1/auth/refresh", s.refresh)
	mux.HandleFunc("POST /v1/auth/logout", s.auth(s.logout))
	mux.HandleFunc("GET /v1/me", s.auth(s.me))
	mux.HandleFunc("DELETE /v1/me", s.auth(s.deleteAccount))
	mux.HandleFunc("POST /v1/sync", s.auth(s.syncRecords))
	mux.HandleFunc("PUT /v1/devices/{id}", s.auth(s.registerDevice))
	mux.HandleFunc("DELETE /v1/devices/{id}", s.auth(s.removeDevice))
	mux.HandleFunc("POST /v1/devices/{id}/test", s.auth(s.testPush))
	mux.HandleFunc("POST /v1/devices/{id}/receipts", s.auth(s.confirmPush))
	if s.cfg.Site != nil {
		mux.Handle("/", s.cfg.Site)
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Frame-Options", "DENY")
		if strings.HasPrefix(r.URL.Path, "/v1/") {
			w.Header().Set("Cache-Control", "no-store")
		}
		if strings.HasPrefix(r.URL.Path, "/v1/auth/") && !s.allow(s.clientAddress(r)) {
			w.Header().Set("Retry-After", "60")
			fail(w, 429, "rate_limited")
			return
		}
		defer func() {
			if recover() != nil {
				slog.Error("request panic", "path", r.URL.Path)
				fail(w, 500, "internal_error")
			}
		}()
		mux.ServeHTTP(w, r)
	})
}
func (s *Server) clientAddress(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	peer := net.ParseIP(host)
	if s.cfg.TrustRelay && peer != nil && peer.IsLoopback() {
		if client := net.ParseIP(r.Header.Get("X-Makeet-Client-IP")); client != nil {
			return client.String()
		}
	}
	return r.RemoteAddr
}
func (s *Server) allow(remote string) bool {
	host, _, err := net.SplitHostPort(remote)
	if err != nil {
		host = remote
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.cfg.Clock()
	b := s.limits[host]
	if b.start.IsZero() && len(s.limits) >= 10000 {
		for key, value := range s.limits {
			if now.Sub(value.start) >= time.Minute {
				delete(s.limits, key)
			}
		}
		if len(s.limits) >= 10000 {
			return false
		}
	}
	if now.Sub(b.start) >= time.Minute {
		b = bucket{start: now}
	}
	b.count++
	s.limits[host] = b
	if len(s.limits) > 10000 {
		for key, value := range s.limits {
			if now.Sub(value.start) > time.Minute {
				delete(s.limits, key)
			}
		}
	}
	return b.count <= 30
}
func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if d.Decode(v) != nil || d.Decode(&struct{}{}) != io.EOF {
		fail(w, 400, "invalid_request")
		return false
	}
	return true
}
func respond(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(value)
}
func fail(w http.ResponseWriter, status int, code string) {
	respond(w, status, map[string]string{"error": code})
}
func randomToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
func hash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}
func internal(w http.ResponseWriter, err error) {
	slog.Error("database operation failed", "type", "storage")
	fail(w, 500, "internal_error")
}

func (s *Server) challenge(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Provider string `json:"provider"`
	}
	if !decode(w, r, &req) {
		return
	}
	if !s.providerAvailable(req.Provider) {
		fail(w, 503, "provider_not_configured")
		return
	}
	raw, err := randomToken()
	if err != nil {
		internal(w, err)
		return
	}
	id := uuid.NewString()
	nonce := hash(raw)
	expiry := s.cfg.Clock().Add(5 * time.Minute).Unix()
	_, err = s.db.ExecContext(r.Context(), "DELETE FROM challenges WHERE expires_at < ?", s.cfg.Clock().Unix())
	if err != nil {
		internal(w, err)
		return
	}
	if _, err = s.db.ExecContext(r.Context(), "DELETE FROM sessions WHERE expires_at<=?", s.cfg.Clock().Unix()); err != nil {
		internal(w, err)
		return
	}
	if _, err = s.db.ExecContext(r.Context(), "DELETE FROM access_tokens WHERE expires_at<=?", s.cfg.Clock().Unix()); err != nil {
		internal(w, err)
		return
	}
	_, err = s.db.ExecContext(r.Context(), "INSERT INTO challenges VALUES(?,?,?,?)", id, req.Provider, nonce, expiry)
	if err != nil {
		internal(w, err)
		return
	}
	respond(w, 201, map[string]any{"id": id, "nonce": nonce, "expires_at": expiry})
}
func (s *Server) exchange(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Provider          string `json:"provider"`
		ChallengeID       string `json:"challenge_id"`
		IDToken           string `json:"id_token"`
		AuthorizationCode string `json:"authorization_code"`
	}
	if !decode(w, r, &req) {
		return
	}
	verifier := s.cfg.Providers[req.Provider]
	if verifier == nil || (req.Provider == "apple" && s.cfg.Apple == nil) {
		fail(w, 503, "provider_not_configured")
		return
	}
	var nonce string
	var expiry int64
	err := s.db.QueryRowContext(r.Context(), "SELECT nonce,expires_at FROM challenges WHERE id=? AND provider=?", req.ChallengeID, req.Provider).Scan(&nonce, &expiry)
	if err != nil || expiry <= s.cfg.Clock().Unix() {
		fail(w, 401, "invalid_challenge")
		return
	}
	who, err := verifier.Verify(r.Context(), req.IDToken, nonce)
	if err != nil {
		fail(w, 401, "invalid_identity")
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w, err)
		return
	}
	defer tx.Rollback()
	res, err := tx.ExecContext(r.Context(), "DELETE FROM challenges WHERE id=? AND provider=? AND expires_at>?", req.ChallengeID, req.Provider, s.cfg.Clock().Unix())
	if err != nil {
		internal(w, err)
		return
	}
	n, _ := res.RowsAffected()
	if n != 1 {
		fail(w, 401, "invalid_challenge")
		return
	}
	var providerToken string
	if req.Provider == "apple" {
		providerToken, err = s.cfg.Apple.Exchange(r.Context(), req.AuthorizationCode, nonce, who, verifier)
		if err != nil {
			if errors.Is(err, apple.ErrRejected) {
				fail(w, 401, "invalid_authorization")
			} else {
				fail(w, 503, "provider_unavailable")
			}
			return
		}
	}
	u := user{Email: who.Email}
	err = tx.QueryRowContext(r.Context(), "SELECT user_id FROM identities WHERE provider=? AND subject=?", req.Provider, who.Subject).Scan(&u.ID)
	if errors.Is(err, sql.ErrNoRows) {
		u.ID = uuid.NewString()
		if _, err = tx.ExecContext(r.Context(), "INSERT INTO users VALUES(?,?,?)", u.ID, u.Email, s.cfg.Clock().Unix()); err != nil {
			internal(w, err)
			return
		}
		if _, err = tx.ExecContext(r.Context(), "INSERT INTO identities VALUES(?,?,?)", req.Provider, who.Subject, u.ID); err != nil {
			internal(w, err)
			return
		}
	} else if err != nil {
		internal(w, err)
		return
	} else {
		if err = tx.QueryRowContext(r.Context(), "SELECT email FROM users WHERE id=?", u.ID).Scan(&u.Email); err != nil {
			internal(w, err)
			return
		}
	}
	if providerToken != "" {
		sealed, err := s.cfg.Apple.Seal(u.ID, who.Audience, providerToken)
		if err != nil {
			internal(w, err)
			return
		}
		if _, err = tx.ExecContext(r.Context(), "INSERT INTO provider_grants VALUES(?,?,?,?,?) ON CONFLICT(user_id,provider,audience) DO UPDATE SET token=excluded.token,updated_at=excluded.updated_at", u.ID, "apple", who.Audience, sealed, s.cfg.Clock().Unix()); err != nil {
			internal(w, err)
			return
		}
	}
	result, err := s.issue(r.Context(), tx, u, "")
	if err != nil {
		internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		internal(w, err)
		return
	}
	respond(w, 200, result)
}
func (s *Server) issue(ctx context.Context, tx *sql.Tx, u user, session string) (tokens, error) {
	access, err := randomToken()
	if err != nil {
		return tokens{}, err
	}
	refresh, err := randomToken()
	if err != nil {
		return tokens{}, err
	}
	if session == "" {
		session = uuid.NewString()
		_, err = tx.ExecContext(ctx, "INSERT INTO sessions(id,user_id,refresh_hash,expires_at) VALUES(?,?,?,?)", session, u.ID, hash(refresh), s.cfg.Clock().Add(30*24*time.Hour).Unix())
	} else {
		_, err = tx.ExecContext(ctx, "UPDATE sessions SET refresh_hash=? WHERE id=?", hash(refresh), session)
	}
	if err != nil {
		return tokens{}, err
	}
	_, err = tx.ExecContext(ctx, "INSERT INTO access_tokens VALUES(?,?,?)", hash(access), session, s.cfg.Clock().Add(15*time.Minute).Unix())
	return tokens{AccessToken: access, RefreshToken: refresh, ExpiresIn: 900, User: u}, err
}
func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !decode(w, r, &req) {
		return
	}
	if len(req.RefreshToken) < 40 {
		fail(w, 401, "invalid_session")
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w, err)
		return
	}
	defer tx.Rollback()
	var session string
	u := user{}
	err = tx.QueryRowContext(r.Context(), "SELECT s.id,u.id,u.email FROM sessions s JOIN users u ON u.id=s.user_id WHERE refresh_hash=? AND revoked=0 AND expires_at>?", hash(req.RefreshToken), s.cfg.Clock().Unix()).Scan(&session, &u.ID, &u.Email)
	if err != nil {
		var reused string
		if tx.QueryRowContext(r.Context(), "SELECT session_id FROM used_refresh WHERE hash=?", hash(req.RefreshToken)).Scan(&reused) == nil {
			if _, err = tx.ExecContext(r.Context(), "UPDATE sessions SET revoked=1 WHERE id=?", reused); err != nil {
				internal(w, err)
				return
			}
			if err = tx.Commit(); err != nil {
				internal(w, err)
				return
			}
		}
		fail(w, 401, "invalid_session")
		return
	}
	if _, err = tx.ExecContext(r.Context(), "INSERT INTO used_refresh VALUES(?,?)", hash(req.RefreshToken), session); err != nil {
		internal(w, err)
		return
	}
	result, err := s.issue(r.Context(), tx, u, session)
	if err != nil {
		internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		internal(w, err)
		return
	}
	respond(w, 200, result)
}
func (s *Server) auth(next func(http.ResponseWriter, *http.Request, principal)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		raw := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if raw == r.Header.Get("Authorization") || len(raw) < 40 {
			fail(w, 401, "unauthorized")
			return
		}
		var p principal
		err := s.db.QueryRowContext(r.Context(), "SELECT s.user_id,s.id FROM access_tokens a JOIN sessions s ON s.id=a.session_id WHERE a.hash=? AND a.expires_at>? AND s.expires_at>? AND s.revoked=0", hash(raw), s.cfg.Clock().Unix(), s.cfg.Clock().Unix()).Scan(&p.UserID, &p.SessionID)
		if err != nil {
			fail(w, 401, "unauthorized")
			return
		}
		next(w, r, p)
	}
}
func (s *Server) me(w http.ResponseWriter, r *http.Request, p principal) {
	u := user{ID: p.UserID}
	if err := s.db.QueryRowContext(r.Context(), "SELECT email FROM users WHERE id=?", p.UserID).Scan(&u.Email); err != nil {
		internal(w, err)
		return
	}
	respond(w, 200, u)
}
func (s *Server) logout(w http.ResponseWriter, r *http.Request, p principal) {
	if _, err := s.db.ExecContext(r.Context(), "DELETE FROM devices WHERE session_id=? AND user_id=?", p.SessionID, p.UserID); err != nil {
		internal(w, err)
		return
	}
	if _, err := s.db.ExecContext(r.Context(), "UPDATE sessions SET revoked=1 WHERE id=? AND user_id=?", p.SessionID, p.UserID); err != nil {
		internal(w, err)
		return
	}
	w.WriteHeader(204)
}
func (s *Server) deleteAccount(w http.ResponseWriter, r *http.Request, p principal) {
	var req struct {
		Confirmation string `json:"confirmation"`
	}
	if !decode(w, r, &req) {
		return
	}
	if req.Confirmation != "DELETE" {
		fail(w, 400, "confirmation_required")
		return
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w, err)
		return
	}
	defer tx.Rollback()
	if err := s.revokeApple(r.Context(), tx, p.UserID); err != nil {
		fail(w, 503, "provider_revocation_unavailable")
		return
	}
	if _, err := tx.ExecContext(r.Context(), "DELETE FROM users WHERE id=?", p.UserID); err != nil {
		internal(w, err)
		return
	}
	if err := tx.Commit(); err != nil {
		internal(w, err)
		return
	}
	w.WriteHeader(204)
}

func (s *Server) revokeApple(ctx context.Context, tx *sql.Tx, userID string) error {
	rows, err := tx.QueryContext(ctx, "SELECT audience,token FROM provider_grants WHERE user_id=? AND provider='apple'", userID)
	if err != nil {
		return err
	}
	type grant struct {
		audience string
		token    []byte
	}
	grants := []grant{}
	for rows.Next() {
		var g grant
		if err := rows.Scan(&g.audience, &g.token); err != nil {
			rows.Close()
			return err
		}
		grants = append(grants, g)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return err
	}
	for _, g := range grants {
		if s.cfg.Apple == nil {
			return apple.ErrUnavailable
		}
		token, err := s.cfg.Apple.Open(userID, g.audience, g.token)
		if err != nil {
			return err
		}
		if err := s.cfg.Apple.Revoke(ctx, g.audience, token); err != nil {
			return err
		}
	}
	var identities int
	if err := tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM identities WHERE user_id=? AND provider='apple'", userID).Scan(&identities); err != nil {
		return err
	}
	if identities > 0 && len(grants) == 0 {
		return apple.ErrUnavailable
	}
	return nil
}

func (s *Server) providerAvailable(name string) bool {
	return s.cfg.Providers[name] != nil && (name != "apple" || s.cfg.Apple != nil)
}
