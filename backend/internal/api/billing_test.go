package api_test

import (
	"encoding/json"
	"github.com/google/uuid"
	"github.com/turinglabsorg/makeet/backend/internal/api"
	"github.com/turinglabsorg/makeet/backend/internal/billing"
	"github.com/turinglabsorg/makeet/backend/internal/identity"
	"github.com/turinglabsorg/makeet/backend/internal/testbilling"
	"net/http/httptest"
	"testing"
	"time"
)

func TestSubscriptionOwnershipExpiryRefundReplayAndFreeDataAccess(t *testing.T) {
	f := setup(t)
	a := f.login("google", "subscription-a")
	b := f.login("google", "subscription-b")
	f.sync(a, 0, []api.Record{habit(uuid.NewString(), 0)})
	issuer := testbilling.New(t, f.now)
	f.server.Close()
	f.api = api.New(f.db, api.Config{Billing: issuer.Verifier, Clock: func() time.Time { return f.now }, Providers: map[string]identity.Verifier{}})
	f.server = httptest.NewServer(f.api.Handler())
	get := func(token string) bool {
		var value struct{ Active bool }
		json.Unmarshal(f.request("GET", "/v1/me/entitlement", token, nil, 200), &value)
		return value.Active
	}
	if get(a.Access) {
		t.Fatal("free account gained Plus")
	}
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{}, 403)
	f.request("GET", "/v1/me/export", a.Access, nil, 200)
	f.request("GET", "/v1/me/profile", a.Access, nil, 200)
	p := testbilling.Purchase(a.User.ID, f.now)
	signed := issuer.Sign(t, p)
	submit := func(token, raw string, status int) {
		f.request("POST", "/v1/me/transactions", token, map[string]string{"signed_transaction": raw}, status)
	}
	submit(b.Access, signed, 403)
	submit(a.Access, signed, 200)
	submit(a.Access, signed, 200)
	if !get(a.Access) || get(b.Access) {
		t.Fatal("entitlement isolation failed")
	}
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{MutationID: uuid.NewString()}, 200)
	notification := billing.Notification{UUID: uuid.NewString(), Type: "REFUND", SignedDate: f.now.Add(time.Second).UnixMilli()}
	notification.Data.BundleID = p.BundleID
	notification.Data.AppID = 0
	notification.Data.Environment = p.Environment
	notification.Data.Transaction = signed
	f.request("POST", "/v1/app-store/notifications", "", map[string]string{"signedPayload": issuer.Sign(t, notification)}, 204)
	submit(a.Access, signed, 200)
	if get(a.Access) {
		t.Fatal("replay revived refunded purchase")
	}
	p.SignedDate = f.now.Add(2 * time.Second).UnixMilli()
	p.RevocationDate = f.now.UnixMilli()
	submit(a.Access, issuer.Sign(t, p), 200)
	if get(a.Access) {
		t.Fatal("revoked purchase remained active")
	}
	p.OriginalID = "renewal"
	p.ID = "new"
	p.RevocationDate = 0
	p.ExpiresDate = f.now.Add(time.Minute).UnixMilli()
	submit(a.Access, issuer.Sign(t, p), 200)
	if !get(a.Access) {
		t.Fatal("renewal missing")
	}
	f.now = f.now.Add(2 * time.Minute)
	if get(a.Access) {
		t.Fatal("expired purchase remained active")
	}
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{}, 403)
	f.request("GET", "/v1/me/export", a.Access, nil, 200)
	f.request("DELETE", "/v1/me", b.Access, map[string]string{"confirmation": "DELETE"}, 204)
}

func TestBillingPreviewOnlyEnablesNamedAccountsAndDoesNotPublishCharging(t *testing.T) {
	f := setup(t)
	a := f.login("google", "preview-owner")
	b := f.login("google", "ordinary-preview")
	issuer := testbilling.New(t, f.now)
	f.server.Close()
	f.api = api.New(f.db, api.Config{Billing: issuer.Verifier, BillingPreviewUsers: map[string]bool{a.User.ID: true}, Clock: func() time.Time { return f.now }})
	f.server = httptest.NewServer(f.api.Handler())
	var config struct {
		Billing bool `json:"billing_enabled"`
	}
	json.Unmarshal(f.request("GET", "/v1/config", "", nil, 200), &config)
	if config.Billing {
		t.Fatal("preview enabled public billing")
	}
	var owner, ordinary struct {
		Enabled bool `json:"billing_enabled"`
		Active  bool `json:"active"`
	}
	json.Unmarshal(f.request("GET", "/v1/me/entitlement", a.Access, nil, 200), &owner)
	json.Unmarshal(f.request("GET", "/v1/me/entitlement", b.Access, nil, 200), &ordinary)
	if !owner.Enabled || owner.Active || ordinary.Enabled {
		t.Fatal("preview isolation failed")
	}
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{}, 403)
	f.sync(b, 0, []api.Record{habit(uuid.NewString(), 0)})
	signed := issuer.Sign(t, testbilling.Purchase(a.User.ID, f.now))
	f.request("POST", "/v1/me/transactions", a.Access, map[string]string{"signed_transaction": signed}, 200)
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{}, 200)
	purchase := testbilling.Purchase(b.User.ID, f.now)
	purchase.OriginalID = "other"
	purchase.ID = "other"
	f.request("POST", "/v1/me/transactions", b.Access, map[string]string{"signed_transaction": issuer.Sign(t, purchase)}, 403)
	event := billing.Notification{UUID: uuid.NewString(), Type: "DID_RENEW", SignedDate: f.now.UnixMilli()}
	event.Data.BundleID = purchase.BundleID
	event.Data.Environment = "Sandbox"
	event.Data.Transaction = issuer.Sign(t, purchase)
	f.request("POST", "/v1/app-store/notifications", "", map[string]string{"signedPayload": issuer.Sign(t, event)}, 204)
	var count int
	if err := f.db.QueryRow("SELECT count(*) FROM subscriptions WHERE user_id=?", b.User.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("unapproved Sandbox notification stored", err)
	}
}

func TestExpiredSubscriberCanExportAndEraseItsDataWithoutAffectingAnotherAccount(t *testing.T) {
	f := setup(t)
	a := f.login("google", "expired-subscriber")
	b := f.login("google", "retained-neighbor")
	f.sync(a, 0, []api.Record{habit(uuid.NewString(), 0)})
	f.sync(b, 0, []api.Record{habit(uuid.NewString(), 0)})
	issuer := testbilling.New(t, f.now)
	f.server.Close()
	f.api = api.New(f.db, api.Config{Billing: issuer.Verifier, Clock: func() time.Time { return f.now }})
	f.server = httptest.NewServer(f.api.Handler())
	p := testbilling.Purchase(a.User.ID, f.now)
	p.ExpiresDate = f.now.Add(time.Minute).UnixMilli()
	f.request("POST", "/v1/me/transactions", a.Access, map[string]string{"signed_transaction": issuer.Sign(t, p)}, 200)
	f.now = f.now.Add(2 * time.Minute)
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{}, 403)
	var exported struct{ Records []api.Record }
	json.Unmarshal(f.request("GET", "/v1/me/export", a.Access, nil, 200), &exported)
	if len(exported.Records) != 1 {
		t.Fatal("expired account lost export")
	}
	f.request("DELETE", "/v1/me", a.Access, map[string]string{"confirmation": "DELETE"}, 204)
	for _, table := range []string{"users", "identities", "sessions", "records", "changes", "batches", "subscriptions"} {
		column := "user_id"
		if table == "users" {
			column = "id"
		}
		var count int
		if err := f.db.QueryRow("SELECT count(*) FROM "+table+" WHERE "+column+"=?", a.User.ID).Scan(&count); err != nil || count != 0 {
			t.Fatalf("%s retained deleted subscriber data: %v", table, err)
		}
	}
	f.request("GET", "/v1/me", a.Access, nil, 401)
	json.Unmarshal(f.request("GET", "/v1/me/export", b.Access, nil, 200), &exported)
	if len(exported.Records) != 1 {
		t.Fatal("deletion affected another account")
	}
	event := billing.Notification{UUID: uuid.NewString(), Type: "DID_RENEW", SignedDate: f.now.UnixMilli()}
	event.Data.BundleID = p.BundleID
	event.Data.Environment = "Sandbox"
	event.Data.Transaction = issuer.Sign(t, p)
	f.request("POST", "/v1/app-store/notifications", "", map[string]string{"signedPayload": issuer.Sign(t, event)}, 204)
	var count int
	f.db.QueryRow("SELECT count(*) FROM subscriptions WHERE user_id=?", a.User.ID).Scan(&count)
	if count != 0 {
		t.Fatal("notification resurrected erased subscriber")
	}
}

func TestProductionEntitlementDoesNotUseStoredSandboxPurchase(t *testing.T) {
	f := setup(t)
	a := f.login("google", "sandbox-explicit")
	issuer := testbilling.New(t, f.now)
	f.server.Close()
	f.api = api.New(f.db, api.Config{Billing: issuer.Verifier, Clock: func() time.Time { return f.now }})
	f.server = httptest.NewServer(f.api.Handler())
	f.request("POST", "/v1/me/transactions", a.Access, map[string]string{"signed_transaction": issuer.Sign(t, testbilling.Purchase(a.User.ID, f.now))}, 200)
	f.server.Close()
	productionVerifier := *issuer.Verifier
	productionVerifier.Sandbox = false
	f.api = api.New(f.db, api.Config{Billing: &productionVerifier, Clock: func() time.Time { return f.now }})
	f.server = httptest.NewServer(f.api.Handler())
	var e struct{ Active bool }
	json.Unmarshal(f.request("GET", "/v1/me/entitlement", a.Access, nil, 200), &e)
	if e.Active {
		t.Fatal("Sandbox receipt granted production entitlement")
	}
	f.request("POST", "/v1/sync", a.Access, api.SyncRequest{}, 403)
}
