package api

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"html/template"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const appleWebCallback = "https://api.makeet.app/v1/auth/apple/callback"

type appleWebFlow struct {
	ID, StateHash, ChallengeID, Nonce, ProofHash, Language string
	Code, IDToken, ProviderError                           string
	Expires                                                time.Time
}

func (s *Server) appleWebEnabled() bool {
	return s.cfg.AppleWebClientID != "" && s.providerAvailable("apple")
}

func webRandom() (string, error) {
	value := make([]byte, 32)
	if _, err := rand.Read(value); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(value), nil
}

func webProof(value string) string {
	sum := sha256.Sum256([]byte(value))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func (s *Server) pruneAppleWeb() {
	for id, flow := range s.webFlows {
		if !s.cfg.Clock().Before(flow.Expires) {
			delete(s.webFlows, id)
		}
	}
}

func (s *Server) startAppleWeb(w http.ResponseWriter, r *http.Request) {
	if !s.appleWebEnabled() {
		fail(w, 503, "provider_unavailable")
		return
	}
	var req struct {
		ChallengeID   string `json:"challenge_id"`
		CodeChallenge string `json:"code_challenge"`
		Language      string `json:"language"`
	}
	if !decode(w, r, &req) {
		return
	}
	proof, err := base64.RawURLEncoding.DecodeString(req.CodeChallenge)
	if err != nil || len(proof) != 32 {
		fail(w, 400, "invalid_proof")
		return
	}
	var nonce string
	var expiry int64
	if s.db.QueryRowContext(r.Context(), "SELECT nonce,expires_at FROM challenges WHERE id=? AND provider='apple'", req.ChallengeID).Scan(&nonce, &expiry) != nil || expiry <= s.cfg.Clock().Unix() {
		fail(w, 400, "invalid_challenge")
		return
	}
	id, err := webRandom()
	if err != nil {
		internal(w, err)
		return
	}
	state, err := webRandom()
	if err != nil {
		internal(w, err)
		return
	}
	flow := &appleWebFlow{ID: id, StateHash: webProof(state), ChallengeID: req.ChallengeID, Nonce: nonce, ProofHash: req.CodeChallenge, Language: req.Language, Expires: time.Unix(expiry, 0)}
	s.webMu.Lock()
	s.pruneAppleWeb()
	if len(s.webFlows) >= 256 {
		s.webMu.Unlock()
		fail(w, 503, "temporarily_unavailable")
		return
	}
	for _, existing := range s.webFlows {
		if existing.ChallengeID == flow.ChallengeID {
			s.webMu.Unlock()
			fail(w, 409, "flow_exists")
			return
		}
	}
	s.webFlows[id] = flow
	s.webMu.Unlock()
	query := url.Values{"client_id": {s.cfg.AppleWebClientID}, "redirect_uri": {appleWebCallback}, "response_type": {"code id_token"}, "response_mode": {"form_post"}, "scope": {"name email"}, "state": {state}, "nonce": {nonce}}
	respond(w, 201, map[string]string{"id": id, "authorization_url": "https://appleid.apple.com/auth/authorize?" + query.Encode()})
}

func (s *Server) callbackAppleWeb(w http.ResponseWriter, r *http.Request) {
	if !s.appleWebEnabled() {
		fail(w, 503, "provider_unavailable")
		return
	}
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/x-www-form-urlencoded") {
		fail(w, 415, "invalid_content_type")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	if r.ParseForm() != nil {
		fail(w, 400, "invalid_callback")
		return
	}
	state := r.PostForm.Get("state")
	if len(state) != 43 {
		fail(w, 400, "invalid_state")
		return
	}
	digest := webProof(state)
	s.webMu.Lock()
	s.pruneAppleWeb()
	var flow *appleWebFlow
	for _, candidate := range s.webFlows {
		if subtle.ConstantTimeCompare([]byte(candidate.StateHash), []byte(digest)) == 1 {
			flow = candidate
			break
		}
	}
	if flow == nil {
		s.webMu.Unlock()
		fail(w, 400, "invalid_state")
		return
	}
	if flow.Code != "" || flow.ProviderError != "" {
		s.webMu.Unlock()
		fail(w, 409, "callback_used")
		return
	}
	nonce, id := flow.Nonce, flow.ID
	s.webMu.Unlock()
	code, token := r.PostForm.Get("code"), r.PostForm.Get("id_token")
	providerError := r.PostForm.Get("error")
	if providerError == "" {
		if code == "" || len(code) > 4096 || token == "" || len(token) > 16384 {
			fail(w, 400, "invalid_callback")
			return
		}
		who, err := s.cfg.Providers["apple"].Verify(r.Context(), token, nonce)
		if err != nil || who.Audience != s.cfg.AppleWebClientID {
			fail(w, 401, "invalid_identity")
			return
		}
	}
	s.webMu.Lock()
	current := s.webFlows[id]
	if current != flow || !s.cfg.Clock().Before(flow.Expires) || flow.Code != "" || flow.ProviderError != "" {
		s.webMu.Unlock()
		fail(w, 409, "callback_used")
		return
	}
	if providerError != "" {
		flow.ProviderError = "provider_cancelled"
	} else {
		flow.Code, flow.IDToken = code, token
	}
	language := flow.Language
	s.webMu.Unlock()
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
	copy := map[string][2]string{
		"en": {"Return to Makeet", "Continue in the app to finish signing in."},
		"it": {"Torna a Makeet", "Continua nell’app per completare l’accesso."},
		"fr": {"Revenir à Makeet", "Continuez dans l’application pour terminer la connexion."},
		"de": {"Zurück zu Makeet", "Schließe die Anmeldung in der App ab."},
		"es": {"Volver a Makeet", "Continúa en la app para finalizar el acceso."},
	}[language]
	if copy[0] == "" {
		copy = [2]string{"Return to Makeet", "Continue in the app to finish signing in."}
	}
	if err := appleReturnPage.Execute(w, copy); err != nil {
		return
	}
}

var appleReturnPage = template.Must(template.New("apple-return").Parse(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Makeet</title><style>body{background:#f7f5ef;color:#233b32;font-family:system-ui,sans-serif;margin:0;padding:48px 24px}main{max-width:480px;margin:8vh auto}a{display:inline-block;padding:16px 24px;border-radius:14px;background:#376b50;color:white;text-decoration:none}p{line-height:1.6}</style></head><body><main><h1>Makeet</h1><p>{{index . 1}}</p><a href="makeet://apple/complete">{{index . 0}}</a></main></body></html>`))

func (s *Server) resultAppleWeb(w http.ResponseWriter, r *http.Request) {
	if !s.appleWebEnabled() {
		fail(w, 503, "provider_unavailable")
		return
	}
	var req struct {
		ID           string `json:"id"`
		CodeVerifier string `json:"code_verifier"`
	}
	if !decode(w, r, &req) {
		return
	}
	if len(req.CodeVerifier) < 43 || len(req.CodeVerifier) > 128 {
		fail(w, 400, "invalid_proof")
		return
	}
	for _, c := range req.CodeVerifier {
		if !strings.ContainsRune("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~", c) {
			fail(w, 400, "invalid_proof")
			return
		}
	}
	proof := webProof(req.CodeVerifier)
	s.webMu.Lock()
	defer s.webMu.Unlock()
	s.pruneAppleWeb()
	flow := s.webFlows[req.ID]
	if flow == nil || subtle.ConstantTimeCompare([]byte(proof), []byte(flow.ProofHash)) != 1 {
		fail(w, 404, "flow_not_found")
		return
	}
	if flow.ProviderError != "" {
		delete(s.webFlows, req.ID)
		fail(w, 403, flow.ProviderError)
		return
	}
	if flow.Code == "" {
		respond(w, 202, map[string]string{"status": "pending"})
		return
	}
	delete(s.webFlows, req.ID)
	respond(w, 200, map[string]string{"status": "ready", "id_token": flow.IDToken, "authorization_code": flow.Code})
}

func (s *Server) appleRedirect(audience string) string {
	if s.cfg.AppleWebClientID != "" && audience == s.cfg.AppleWebClientID {
		return appleWebCallback
	}
	return ""
}
