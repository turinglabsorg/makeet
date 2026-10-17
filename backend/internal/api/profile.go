package api

import (
	"bytes"
	"database/sql"
	"errors"
	"image"
	"image/jpeg"
	_ "image/png"
	"net/http"
	"strings"
	"unicode"
	"unicode/utf8"
)

type Profile struct {
	Name     string `json:"name"`
	Image    []byte `json:"image"`
	Revision int64  `json:"revision"`
}

func (s *Server) getProfile(w http.ResponseWriter, r *http.Request, p principal) {
	var profile Profile
	err := s.db.QueryRowContext(r.Context(), "SELECT name,image,revision FROM profiles WHERE user_id=?", p.UserID).Scan(&profile.Name, &profile.Image, &profile.Revision)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		internal(w, err)
		return
	}
	respond(w, 200, profile)
}

func (s *Server) updateProfile(w http.ResponseWriter, r *http.Request, p principal) {
	var profile Profile
	if !decode(w, r, &profile) {
		return
	}
	profile.Name = strings.TrimSpace(profile.Name)
	if profile.Revision < 0 || utf8.RuneCountInString(profile.Name) > 80 || strings.ContainsFunc(profile.Name, unicode.IsControl) || len(profile.Image) > 128*1024 {
		fail(w, 422, "invalid_profile")
		return
	}
	if len(profile.Image) > 0 {
		config, format, err := image.DecodeConfig(bytes.NewReader(profile.Image))
		if err != nil || (format != "jpeg" && format != "png") || config.Width < 1 || config.Height < 1 || config.Width > 512 || config.Height > 512 {
			fail(w, 422, "invalid_profile_image")
			return
		}
		decoded, _, err := image.Decode(bytes.NewReader(profile.Image))
		if err != nil {
			fail(w, 422, "invalid_profile_image")
			return
		}
		var normalized bytes.Buffer
		for _, quality := range []int{85, 75, 60} {
			normalized.Reset()
			if err = jpeg.Encode(&normalized, decoded, &jpeg.Options{Quality: quality}); err != nil {
				internal(w, err)
				return
			}
			if normalized.Len() <= 128*1024 {
				break
			}
		}
		if normalized.Len() > 128*1024 {
			fail(w, 422, "invalid_profile_image")
			return
		}
		profile.Image = normalized.Bytes()
	} else {
		profile.Image = nil
	}
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		internal(w, err)
		return
	}
	defer tx.Rollback()
	var revision int64
	err = tx.QueryRowContext(r.Context(), "SELECT revision FROM profiles WHERE user_id=?", p.UserID).Scan(&revision)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		internal(w, err)
		return
	}
	if profile.Revision != revision {
		fail(w, 409, "profile_conflict")
		return
	}
	profile.Revision++
	_, err = tx.ExecContext(r.Context(), "INSERT INTO profiles VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET name=excluded.name,image=excluded.image,revision=excluded.revision", p.UserID, profile.Name, profile.Image, profile.Revision)
	if err != nil {
		internal(w, err)
		return
	}
	if err = tx.Commit(); err != nil {
		internal(w, err)
		return
	}
	respond(w, 200, profile)
}
