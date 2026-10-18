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
