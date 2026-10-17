package push_test

import (
	"context"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/turinglabsorg/makeet/backend/internal/testidentity"
)

func TestSignedAPNsRequestsReuseAuthorizationAndClassifyTokenRejection(t *testing.T) {
	f := testidentity.NewPush(t)
	token := strings.Repeat("ab", 32)
	for _, status := range []int32{200, 410, 503} {
		f.Status.Store(status)
		result, err := f.Client.Send(context.Background(), "org.turinglabs.makeet", token, uuid.NewString(), []byte(`{"aps":{"alert":{"title":"Makeet","body":"Test"}}}`))
		if err != nil || result.Accepted != (status == 200) || result.InvalidToken != (status == 410) || result.Retryable != (status == 503) {
			t.Fatalf("unexpected APNs classification for %d", status)
		}
	}
	if f.Client.Available("another.topic", "development") || f.Client.Available("org.turinglabs.makeet", "production") {
		t.Fatal("APNs scope expanded")
	}
	_, _, first := f.Snapshot()
	f.Status.Store(200)
	if _, err := f.Client.Send(context.Background(), "org.turinglabs.makeet", token, uuid.NewString(), []byte(`{"aps":{"alert":"Test"}}`)); err != nil {
		t.Fatal(err)
	}
	_, _, second := f.Snapshot()
	if first != second {
		t.Fatal("APNs provider assertion rotated for every request")
	}
}

func TestDeviceTokenEncryptionIsBoundToAccountDeviceAndTopic(t *testing.T) {
	f := testidentity.NewPush(t)
	sealed, err := f.Client.Seal("account", "device", "org.turinglabs.makeet", "fixture-token")
	if err != nil {
		t.Fatal(err)
	}
	if token, err := f.Client.Open("account", "device", "org.turinglabs.makeet", sealed); err != nil || token != "fixture-token" {
		t.Fatal("cannot recover own device token")
	}
	for _, scope := range [][3]string{{"other", "device", "org.turinglabs.makeet"}, {"account", "other", "org.turinglabs.makeet"}, {"account", "device", "other"}} {
		if _, err := f.Client.Open(scope[0], scope[1], scope[2], sealed); err == nil {
			t.Fatal("device token escaped its scope")
		}
	}
}
