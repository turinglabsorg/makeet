package main

import (
	"bytes"
	"encoding/base64"
	"encoding/hex"
	"testing"
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
