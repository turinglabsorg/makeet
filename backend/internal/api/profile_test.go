package api_test

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"math/rand"
	"strings"
	"testing"

	"github.com/turinglabsorg/makeet/backend/internal/api"
)

func profileImage(width int) []byte {
	img := image.NewNRGBA(image.Rect(0, 0, width, 32))
	img.Set(10, 10, color.NRGBA{R: 30, G: 100, B: 80, A: 255})
	var data bytes.Buffer
	png.Encode(&data, img)
	return data.Bytes()
}

func TestPrivateProfilePersistsAcrossSessionsAndRejectsStaleChanges(t *testing.T) {
	f := setup(t)
	a, b := f.login("google", "profile-a"), f.login("google", "profile-b")
	f.request("GET", "/v1/me/profile", "", nil, 401)
	f.request("PUT", "/v1/me/profile", "", api.Profile{}, 401)
	var empty, saved, loaded api.Profile
	json.Unmarshal(f.request("GET", "/v1/me/profile", a.Access, nil, 200), &empty)
	if empty.Revision != 0 || empty.Image != nil || empty.Name != "" {
		t.Fatal("new profile should be empty")
	}
	request := api.Profile{Name: "  Alex  ", Image: profileImage(32)}
	json.Unmarshal(f.request("PUT", "/v1/me/profile", a.Access, request, 200), &saved)
	if saved.Name != "Alex" || saved.Revision != 1 {
		t.Fatal("profile was not saved")
	}
	if _, err := jpeg.Decode(bytes.NewReader(saved.Image)); err != nil {
		t.Fatal("image was not normalized to JPEG", err)
	}
	second := f.login("google", "profile-a")
	json.Unmarshal(f.request("GET", "/v1/me/profile", second.Access, nil, 200), &loaded)
	if loaded.Name != saved.Name || !bytes.Equal(loaded.Image, saved.Image) {
		t.Fatal("profile did not follow the account")
	}
	json.Unmarshal(f.request("GET", "/v1/me/profile", b.Access, nil, 200), &empty)
	if empty.Revision != 0 || len(empty.Image) != 0 {
		t.Fatal("profile crossed account boundary")
	}
	f.request("PUT", "/v1/me/profile", second.Access, request, 409)
	loaded.Image = nil
	json.Unmarshal(f.request("PUT", "/v1/me/profile", a.Access, loaded, 200), &saved)
	if saved.Image != nil || saved.Revision != 2 {
		t.Fatal("photo removal was not saved")
	}
	f.request("DELETE", "/v1/me", a.Access, map[string]string{"confirmation": "DELETE"}, 204)
	var count int
	if err := f.db.QueryRow("SELECT count(*) FROM profiles WHERE user_id=?", a.User.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("deleted account retained profile")
	}
	f.request("GET", "/v1/me/profile", second.Access, nil, 401)
}

func TestProfileRejectsInvalidImagesAndNamesWithoutChangingSavedData(t *testing.T) {
	f := setup(t)
	a := f.login("google", "invalid-profile")
	for _, bad := range []api.Profile{
		{Name: strings.Repeat("a", 81)}, {Name: "a\nb"}, {Revision: -1},
		{Image: []byte("https://example.invalid/avatar")}, {Image: profileImage(513)}, {Image: make([]byte, 129*1024)},
	} {
		f.request("PUT", "/v1/me/profile", a.Access, bad, 422)
	}
	var profile api.Profile
	json.Unmarshal(f.request("GET", "/v1/me/profile", a.Access, nil, 200), &profile)
	if profile.Revision != 0 {
		t.Fatal("rejected profile changed the database")
	}
}

func TestNormalizedPhotoCanBeSubmittedAgainWithANameChange(t *testing.T) {
	f := setup(t)
	a := f.login("google", "photo-roundtrip")
	img := image.NewNRGBA(image.Rect(0, 0, 512, 512))
	random := rand.New(rand.NewSource(42))
	for index := range img.Pix {
		img.Pix[index] = byte(random.Intn(256))
	}
	var input bytes.Buffer
	jpeg.Encode(&input, img, &jpeg.Options{Quality: 35})
	var profile api.Profile
	json.Unmarshal(f.request("PUT", "/v1/me/profile", a.Access, api.Profile{Image: input.Bytes()}, 200), &profile)
	if len(profile.Image) > 128*1024 {
		t.Fatal("normalized output exceeds its own input limit")
	}
	profile.Name = "Alex"
	f.request("PUT", "/v1/me/profile", a.Access, profile, 200)
}
