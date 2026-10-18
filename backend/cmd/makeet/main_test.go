package main

import (
	"bytes"
	"encoding/base64"
	"encoding/hex"
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestProviderEncryptionConfiguration(t *testing.T) {
	expected := bytes.Repeat([]byte{0xCA}, 32)
	for _, encoded := range []string{hex.EncodeToString(expected), base64.StdEncoding.EncodeToString(expected), base64.RawURLEncoding.EncodeToString(expected)} {
		actual, err := providerKey(encoded)
		if err != nil || !bytes.Equal(expected, actual) {
			t.Fatal("valid provider encryption format rejected")
		}
	}
	for _, invalid := range []string{"", "short", hex.EncodeToString(expected[:16]), base64.StdEncoding.EncodeToString(expected[:24])} {
		if _, err := providerKey(invalid); err == nil {
			t.Fatal("invalid encryption configuration accepted")
		}
	}
}

func TestBillingPreviewConfigurationRejectsUnboundedOrInvalidAccounts(t *testing.T) {
	id := "5c720ee0-b1f6-43ca-ab46-05e80e8af4e6"
	for _, raw := range []string{"", id, " " + id + " , " + id} {
		users, err := billingPreviewUsers(raw)
		if err != nil || len(users) > 1 {
			t.Fatal("valid allowlist rejected", err)
		}
	}
	for _, raw := range []string{"invalid", "00000000-0000-0000-0000-000000000000", id + ","} {
		if _, err := billingPreviewUsers(raw); err == nil {
			t.Fatal("invalid allowlist accepted")
		}
	}
	ids := make([]string, 11)
	for i := range ids {
		ids[i] = uuid.NewString()
	}
	if _, err := billingPreviewUsers(strings.Join(ids, ",")); err == nil {
		t.Fatal("unbounded preview allowlist accepted")
	}
	if users, err := billingPreviewUsers(strings.Join(append(ids[:10:10], ids[0]), ",")); err != nil || len(users) != 10 {
		t.Fatal("duplicate account consumed an extra preview slot", err)
	}
}
