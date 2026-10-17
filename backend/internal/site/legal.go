package site

type LegalCopy struct {
	Updated          string
	PrivacyIntro     string
	ControllerTitle  string
	HostingTitle     string
	TermsIntro       string
	DeletionIntro    string
	PrivacySections  []Section
	TermsSections    []Section
	DeletionSections []Section
}

type Config struct {
	ControllerLine string
	HostingCountry string
}

func (c Config) Ready() bool { return c.ControllerLine != "" && c.HostingCountry != "" }

func hostingCountry(code, language string) string {
	if code == "IT" {
		return map[string]string{"it": "Italia", "en": "Italy", "fr": "Italie", "de": "Italien", "es": "Italia"}[language]
	}
	return code
}
