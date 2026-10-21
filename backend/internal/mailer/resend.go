package mailer

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"
)

type Resend struct {
	key, from string
	http      *http.Client
}

func New(key, from string) (*Resend, error) {
	if strings.TrimSpace(key) == "" || !strings.HasSuffix(from, "@noreply.makeet.app") || strings.ContainsAny(from, "\r\n<> ") {
		return nil, errors.New("invalid mail configuration")
	}
	return &Resend{key: key, from: from, http: &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}, nil
}
func (c *Resend) SendCode(ctx context.Context, email, code, kind, language string) error {
	copy := map[string][3]string{
		"en": {"Makeet verification code", "Your Makeet verification code is: ", "This code expires in 15 minutes. Enter it only in Makeet. If you did not request it, ignore this email."},
		"it": {"Codice di verifica Makeet", "Il tuo codice di verifica Makeet è: ", "Il codice scade tra 15 minuti. Inseriscilo solo in Makeet. Se non lo hai richiesto, ignora questa email."},
		"fr": {"Code de vérification Makeet", "Votre code de vérification Makeet est : ", "Ce code expire dans 15 minutes. Saisissez-le uniquement dans Makeet. Si vous ne l’avez pas demandé, ignorez cet email."},
		"de": {"Makeet-Bestätigungscode", "Dein Makeet-Bestätigungscode lautet: ", "Dieser Code läuft in 15 Minuten ab. Gib ihn nur in Makeet ein. Wenn du ihn nicht angefordert hast, ignoriere diese E-Mail."},
		"es": {"Código de verificación de Makeet", "Tu código de verificación de Makeet es: ", "Este código caduca en 15 minutos. Introdúcelo solo en Makeet. Si no lo has solicitado, ignora este correo."},
	}
	text, ok := copy[language]
	if !ok {
		text = copy["en"]
	}
	data, err := json.Marshal(map[string]any{"from": "Makeet <" + c.from + ">", "to": []string{email}, "subject": text[0], "text": text[1] + code + "\n\n" + text[2]})
	if err != nil {
		return errors.New("email unavailable")
	}
	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.resend.com/emails", bytes.NewReader(data))
	if err != nil {
		return errors.New("email unavailable")
	}
	req.Header.Set("Authorization", "Bearer "+c.key)
	req.Header.Set("Content-Type", "application/json")
	res, err := c.http.Do(req)
	if err != nil {
		return errors.New("email unavailable")
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return errors.New("email unavailable")
	}
	var receipt struct {
		ID string `json:"id"`
	}
	if json.NewDecoder(io.LimitReader(res.Body, 8192)).Decode(&receipt) != nil || receipt.ID == "" {
		return errors.New("email unavailable")
	}
	return nil
}
