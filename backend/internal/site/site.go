package site

import (
	"bytes"
	"embed"
	"encoding/json"
	"html/template"
	"io/fs"
	"net/http"
	"strings"
)

//go:embed templates assets locales
var files embed.FS

type Section struct {
	Title string
	Body  string
}
type CalendarCopy struct {
	Eyebrow, Title, Body, Schedule, Example, Month, Low, High string
	Weekdays                                                  []string
}
type Copy struct {
	Language, Description, Status, Eyebrow, Headline, Intro, Explore, Support, Preview, FeaturesTitle, FeaturesIntro, Future, Footer, Privacy, Terms, Deletion, Back, Email, SupportBody, LegalStatus, LegalBody, NotFound, NotFoundBody string
	Features                                                                                                                                                                                                                             []Section
	Questions                                                                                                                                                                                                                            []Section
	FAQ                                                                                                                                                                                                                                  string
	Policy                                                                                                                                                                                                                               LegalCopy
	Calendar                                                                                                                                                                                                                             CalendarCopy
}
type page struct {
	Copy
	Lang, Path, Title                             string
	Home, Help, Legal, Missing                    bool
	PolicyReady, IsPrivacy                        bool
	ControllerLine, HostingCountry, DocumentIntro string
	DocumentSections                              []Section
}

func New() http.Handler { return WithConfig(Config{}) }

func WithConfig(cfg Config) http.Handler {
	t := template.Must(template.New("page.html").Funcs(template.FuncMap{"inc": func(i int) int { return i + 1 }, "languages": func() []map[string]string {
		return []map[string]string{{"Code": "it", "Name": "Italiano"}, {"Code": "en", "Name": "English"}, {"Code": "fr", "Name": "Français"}, {"Code": "de", "Name": "Deutsch"}, {"Code": "es", "Name": "Español"}}
	}, "marks": func() []int {
		return []int{1, 2, 2, 0, 3, 2, 3, 3, 1, 3, 2, 3, 3, 2, 0, 1, 2, 2, 3, 1, 3, 2, 2, 3, 1, 3, 3, 2, 1, 2, 3, 3, 2, 3, 2, 3, 3, 1, 3, 2, 3, 3}
	}, "month": func() []int {
		return []int{1, 2, 0, 3, 2, 1, 3, 3, 2, 1, 3, 2, 3, 3, 2, 3, 1, 2, 3, 2, 3, 3, 2, 3, 3, 1, 3, 3}
	}}).ParseFS(files, "templates/page.html"))
	translations := map[string]Copy{}
	for _, lang := range []string{"it", "en", "fr", "de", "es"} {
		data, err := files.ReadFile("locales/" + lang + ".json")
		if err != nil {
			panic(err)
		}
		var copy Copy
		if err := json.Unmarshal(data, &copy); err != nil {
			panic(err)
		}
		translations[lang] = copy
	}
	assets, _ := fs.Sub(files, "assets")
	static := http.FileServer(http.FS(assets))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Security-Policy", "default-src 'none'; img-src 'self'; style-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			w.Header().Set("Allow", "GET, HEAD")
			http.Error(w, "Method not allowed", 405)
			return
		}
		if strings.HasPrefix(r.URL.Path, "/assets/") {
			if strings.HasSuffix(r.URL.Path, "/") {
				http.NotFound(w, r)
				return
			}
			w.Header().Set("Cache-Control", "public, max-age=3600")
			http.StripPrefix("/assets/", static).ServeHTTP(w, r)
			return
		}
		if r.URL.Path == "/robots.txt" {
			w.Header().Set("Content-Type", "text/plain; charset=utf-8")
			w.Write([]byte("User-agent: *\nDisallow: /v1/\n"))
			return
		}
		lang := "en"
		parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
		if _, ok := translations[parts[0]]; ok {
			lang = parts[0]
			parts = parts[1:]
		} else if r.URL.Path == "/" {
			for _, preference := range strings.Split(r.Header.Get("Accept-Language"), ",") {
				tag := strings.ToLower(strings.TrimSpace(strings.Split(preference, ";")[0]))
				if len(tag) >= 2 {
					if _, ok := translations[tag[:2]]; ok {
						lang = tag[:2]
						break
					}
				}
			}
			w.Header().Set("Vary", "Accept-Language")
			http.Redirect(w, r, "/"+lang+"/", http.StatusTemporaryRedirect)
			return
		}
		path := strings.Join(parts, "/")
		if path == "" {
			path = "/"
		}
		copy := translations[lang]
		p := page{Copy: copy, Lang: lang, Path: path, Title: "Makeet — " + copy.Description}
		status := 200
		switch path {
		case "/":
			p.Home = true
		case "support":
			p.Help = true
			p.Title = copy.Support + " — Makeet"
		case "privacy", "terms", "delete-account":
			p.Legal = true
			p.PolicyReady = cfg.Ready()
			if p.PolicyReady {
				switch path {
				case "privacy":
					p.IsPrivacy = true
					p.ControllerLine = cfg.ControllerLine
					p.HostingCountry = hostingCountry(cfg.HostingCountry, lang)
					p.Title = copy.Privacy
					p.DocumentIntro = copy.Policy.PrivacyIntro
					p.DocumentSections = copy.Policy.PrivacySections
				case "terms":
					p.Title = copy.Terms
					p.DocumentIntro = copy.Policy.TermsIntro
					p.DocumentSections = copy.Policy.TermsSections
				case "delete-account":
					p.Title = copy.Deletion
					p.DocumentIntro = copy.Policy.DeletionIntro
					p.DocumentSections = copy.Policy.DeletionSections
				}
			} else {
				p.Title = copy.LegalStatus + " — Makeet"
				status = 503
				w.Header().Set("X-Robots-Tag", "noindex")
				w.Header().Set("Retry-After", "86400")
			}
		default:
			p.Missing = true
			p.Title = copy.NotFound + " — Makeet"
			status = 404
		}
		var body bytes.Buffer
		if err := t.Execute(&body, p); err != nil {
			http.Error(w, "Page unavailable", 500)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Content-Language", lang)
		w.Header().Set("Cache-Control", "no-cache")
		w.WriteHeader(status)
		if r.Method != http.MethodHead {
			w.Write(body.Bytes())
		}
	})
}
