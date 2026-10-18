package main

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/google/uuid"

	"github.com/turinglabsorg/makeet/backend/internal/api"
	"github.com/turinglabsorg/makeet/backend/internal/apple"
	"github.com/turinglabsorg/makeet/backend/internal/billing"
	"github.com/turinglabsorg/makeet/backend/internal/identity"
	"github.com/turinglabsorg/makeet/backend/internal/push"
	"github.com/turinglabsorg/makeet/backend/internal/site"
	"github.com/turinglabsorg/makeet/backend/internal/store"
)

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	db, err := store.Open(env("MAKEET_DATABASE", "./data/makeet.sqlite"))
	if err != nil {
		slog.Error("cannot open database")
		os.Exit(1)
	}
	defer db.Close()
	providers := map[string]identity.Verifier{}
	for _, p := range []struct{ name, issuer, keys, env string }{
		{"apple", "https://appleid.apple.com", "https://appleid.apple.com/auth/keys", "MAKEET_APPLE_CLIENT_IDS"},
		{"google", "https://accounts.google.com", "https://www.googleapis.com/oauth2/v3/certs", "MAKEET_GOOGLE_CLIENT_IDS"},
	} {
		if ids := os.Getenv(p.env); ids != "" {
			providers[p.name] = identity.New(ctx, p.issuer, p.keys, strings.Split(ids, ","))
		}
	}
	var appleClient *apple.Client
	if providers["apple"] != nil {
		encryption, decodeErr := providerKey(os.Getenv("MAKEET_PROVIDER_ENCRYPTION_KEY"))
		if decodeErr == nil {
			appleClient, err = apple.New(apple.Config{TeamID: os.Getenv("MAKEET_APPLE_TEAM_ID"), KeyID: os.Getenv("MAKEET_APPLE_KEY_ID"), PrivateKey: []byte(os.Getenv("MAKEET_APPLE_SIGNING_KEY")), EncryptionKey: encryption})
		}
		if decodeErr != nil || err != nil || appleClient == nil {
			slog.Error("Apple sign-in requires signing and provider encryption configuration")
			os.Exit(1)
		}
	}
	var pushClient *push.Client
	if os.Getenv("MAKEET_APNS_ENVIRONMENT") != "" || os.Getenv("MAKEET_APNS_KEY") != "" {
		encryption, decodeErr := providerKey(os.Getenv("MAKEET_PROVIDER_ENCRYPTION_KEY"))
		if decodeErr == nil {
			pushClient, err = push.New(push.Config{TeamID: os.Getenv("MAKEET_APNS_TEAM_ID"), KeyID: os.Getenv("MAKEET_APNS_KEY_ID"), Environment: os.Getenv("MAKEET_APNS_ENVIRONMENT"), PrivateKey: []byte(os.Getenv("MAKEET_APNS_KEY")), EncryptionKey: encryption, Topics: strings.Split(os.Getenv("MAKEET_APNS_TOPICS"), ",")})
		}
		if decodeErr != nil || err != nil || pushClient == nil {
			slog.Error("push requires signing, topic, environment and encryption configuration")
			os.Exit(1)
		}
	}
	siteConfig := site.Config{ControllerLine: os.Getenv("MAKEET_PRIVACY_CONTROLLER"), HostingCountry: os.Getenv("MAKEET_HOSTING_COUNTRY")}
	if len(providers) > 0 && !siteConfig.Ready() {
		slog.Error("accounts require configured privacy information")
		os.Exit(1)
	}
	previewUsers, err := billingPreviewUsers(os.Getenv("MAKEET_BILLING_PREVIEW_USERS"))
	if err != nil {
		slog.Error("invalid billing preview configuration")
		os.Exit(1)
	}
	var subscriptions *billing.Verifier
	if os.Getenv("MAKEET_BILLING_ENABLED") == "true" || len(previewUsers) > 0 {
		subscriptions, err = billing.New(os.Getenv("MAKEET_BILLING_SANDBOX") == "true")
		if err != nil {
			slog.Error("invalid App Store trust configuration")
			os.Exit(1)
		}
	}
	service := api.New(db, api.Config{Billing: subscriptions, BillingPreviewUsers: previewUsers, Providers: providers, Apple: appleClient, Push: pushClient, Site: site.WithConfig(siteConfig), TrustRelay: os.Getenv("MAKEET_TRUST_RELAY") == "true"})
	go service.RunPush(ctx)
	handler := service.Handler()
	server := &http.Server{Addr: env("MAKEET_LISTEN", "127.0.0.1:8086"), Handler: handler, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 20 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16 << 10}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		server.Shutdown(shutdown)
	}()
	slog.Info("makeet starting", "address", server.Addr, "providers", len(providers))
	if err = server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		slog.Error("server stopped")
		os.Exit(1)
	}
}

func providerKey(raw string) ([]byte, error) {
	for _, decode := range []func(string) ([]byte, error){hex.DecodeString, base64.StdEncoding.DecodeString, base64.RawURLEncoding.DecodeString} {
		key, err := decode(raw)
		if err == nil && len(key) == 32 {
			return key, nil
		}
	}
	return nil, errors.New("invalid provider encryption key")
}

func billingPreviewUsers(raw string) (map[string]bool, error) {
	users := map[string]bool{}
	if raw == "" {
		return users, nil
	}
	for _, value := range strings.Split(raw, ",") {
		id, err := uuid.Parse(strings.TrimSpace(value))
		if err != nil || id == uuid.Nil {
			return nil, errors.New("invalid preview account")
		}
		users[id.String()] = true
		if len(users) > 10 {
			return nil, errors.New("too many preview accounts")
		}
	}
	return users, nil
}
