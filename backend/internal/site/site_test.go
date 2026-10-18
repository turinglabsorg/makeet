package site

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPublicSiteOverHTTP(t *testing.T) {
	server := httptest.NewServer(New())
	defer server.Close()
	client := server.Client()
	client.CheckRedirect = func(r *http.Request, via []*http.Request) error { return http.ErrUseLastResponse }
	for _, lang := range []string{"it", "en", "fr", "de", "es"} {
		for _, page := range []string{"", "support", "privacy", "terms", "delete-account", "missing"} {
			t.Run(lang+"/"+page, func(t *testing.T) {
				res, err := client.Get(server.URL + "/" + lang + "/" + page)
				if err != nil {
					t.Fatal(err)
				}
				defer res.Body.Close()
				body, _ := io.ReadAll(res.Body)
				status := 200
				if page == "privacy" || page == "terms" || page == "delete-account" {
					status = 503
				}
				if page == "missing" {
					status = 404
				}
				if res.StatusCode != status {
					t.Fatalf("status %d: %s", res.StatusCode, body)
				}
				if res.Header.Get("Content-Language") != lang || !strings.Contains(string(body), `<html lang="`+lang+`">`) {
					t.Fatal("wrong language")
				}
				for _, other := range []string{"it", "en", "fr", "de", "es"} {
					if !strings.Contains(string(body), `href="/`+other+`/`+page+`"`) {
						t.Fatalf("missing language link %s", other)
					}
				}
				if !strings.Contains(string(body), "Meaningtech") || strings.Contains(string(body), "<no value>") {
					t.Fatal("incomplete template")
				}
				if res.Header.Get("Content-Security-Policy") == "" {
					t.Fatal("missing security policy")
				}
				if status == 503 && res.Header.Get("X-Robots-Tag") != "noindex" {
					t.Fatal("pending legal content must not be indexed")
				}
			})
		}
	}
	req, _ := http.NewRequest("GET", server.URL+"/", nil)
	req.Header.Set("Accept-Language", "fr-CH,fr;q=0.9,en;q=0.8")
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != 307 || res.Header.Get("Location") != "/fr/" {
		t.Fatal("language redirect")
	}
	for _, asset := range []string{"style.css", "today.png", "today-preview10.png", "icon.png"} {
		res, err := client.Get(server.URL + "/assets/" + asset)
		if err != nil {
			t.Fatal(err)
		}
		b, _ := io.ReadAll(res.Body)
		res.Body.Close()
		if res.StatusCode != 200 || len(b) == 0 {
			t.Fatalf("missing asset %s", asset)
		}
	}
	for _, method := range []string{"POST", "PUT", "DELETE"} {
		req, _ := http.NewRequest(method, server.URL+"/en/", nil)
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		if res.StatusCode != 405 {
			t.Fatalf("unsafe method accepted %s", method)
		}
	}
	req, _ = http.NewRequest("HEAD", server.URL+"/en/", nil)
	res, err = client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if len(b) != 0 || res.StatusCode != 200 {
		t.Fatal("HEAD response")
	}
}

func TestConfiguredPoliciesIdentifyControllerOnlyOnPrivacy(t *testing.T) {
	const controller = "Example Controller & Trading Name. Contact: support@example.invalid"
	server := httptest.NewServer(WithConfig(Config{ControllerLine: controller, HostingCountry: "Italia (IT)"}))
	defer server.Close()
	for _, lang := range []string{"it", "en", "fr", "de", "es"} {
		for _, path := range []string{"", "support", "privacy", "terms", "delete-account", "missing"} {
			res, err := server.Client().Get(server.URL + "/" + lang + "/" + path)
			if err != nil {
				t.Fatal(err)
			}
			raw, _ := io.ReadAll(res.Body)
			res.Body.Close()
			body := string(raw)
			status := 200
			if path == "missing" {
				status = 404
			}
			if res.StatusCode != status {
				t.Fatalf("%s/%s returned %d", lang, path, res.StatusCode)
			}
			contains := strings.Contains(body, "Example Controller &amp; Trading Name")
			if contains != (path == "privacy") {
				t.Fatalf("controller scope violated on %s/%s", lang, path)
			}
			if path == "privacy" && (!strings.Contains(body, "Italia (IT)") || !strings.Contains(body, "cloudflare-customer-dpa")) {
				t.Fatal("missing hosting or source links")
			}
			if strings.Contains(body, "<no value>") {
				t.Fatal("incomplete legal template")
			}
		}
	}
}
func TestPartialPolicyConfigurationStaysClosed(t *testing.T) {
	for _, cfg := range []Config{{ControllerLine: "Example Controller"}, {HostingCountry: "IT"}} {
		req := httptest.NewRequest("GET", "/en/privacy", nil)
		w := httptest.NewRecorder()
		WithConfig(cfg).ServeHTTP(w, req)
		if w.Code != 503 || strings.Contains(w.Body.String(), "Example Controller") {
			t.Fatal("partial policy configuration exposed")
		}
	}
}
