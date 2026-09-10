package main

import (
	"math/rand"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestParseSubscriptionBodyDeduplicatesAndRejectsUnsupportedSchemes(t *testing.T) {
	body := []byte(strings.Join([]string{
		"vless://id@example.com:443?security=tls#first",
		"vless://id@example.com:443?security=tls#duplicate remark",
		"tuic://id:secret@example.com:443",
		"not-a-proxy",
		"ss://YWVzLTEyOC1nY206cGFzcw@example.com:8388",
	}, "\n"))

	contents, err := parseSubscriptionBody(body)
	if err != nil {
		t.Fatalf("parseSubscriptionBody returned error: %v", err)
	}
	if got, want := len(contents.URIs), 2; got != want {
		t.Fatalf("URI count = %d, want %d (%v)", got, want, contents.URIs)
	}
	if got, want := contents.Duplicates, 1; got != want {
		t.Errorf("duplicates = %d, want %d", got, want)
	}
	if got, want := contents.Unsupported, 1; got != want {
		t.Errorf("unsupported = %d, want %d", got, want)
	}
}

func TestFetchSubscriptionRetriesTransientHTTPStatus(t *testing.T) {
	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		attempts++
		if attempts < 3 {
			response.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		_, _ = response.Write([]byte("vless://id@example.com:443"))
	}))
	defer server.Close()

	body, err := fetchSubscriptionBody(server.Client(), server.URL, 0)
	if err != nil {
		t.Fatalf("fetchSubscriptionBody returned error: %v", err)
	}
	if attempts != 3 || !strings.Contains(string(body), "vless://") {
		t.Fatalf("attempts = %d, body = %q", attempts, body)
	}
}

func TestSampleExactlyReturnsRequestedCountWithoutMutatingInput(t *testing.T) {
	input := []string{"a", "b", "c", "d", "e", "f"}
	original := append([]string(nil), input...)

	got := sampleExactly(input, 4, rand.New(rand.NewSource(7)))
	if len(got) != 4 {
		t.Fatalf("sample length = %d, want 4", len(got))
	}
	for i := range input {
		if input[i] != original[i] {
			t.Fatalf("input mutated: got %v, want %v", input, original)
		}
	}
}

func TestValidateHTTPURL(t *testing.T) {
	for _, raw := range []string{"", "file:///tmp/sub.txt", "https:///missing-host"} {
		if err := validateHTTPURL(raw, "subscription URL"); err == nil {
			t.Errorf("validateHTTPURL(%q) succeeded, want error", raw)
		}
	}
	if err := validateHTTPURL("https://example.com/sub?token=secret", "subscription URL"); err != nil {
		t.Fatalf("valid URL rejected: %v", err)
	}
}

func TestRedactURLRemovesCredentialsAndQuery(t *testing.T) {
	got := redactURL("https://user:pass@example.com/sub?token=secret#fragment")
	if strings.Contains(got, "pass") || strings.Contains(got, "secret") || strings.Contains(got, "user") {
		t.Fatalf("redacted URL leaked sensitive data: %q", got)
	}
	if got != "https://example.com/sub" {
		t.Fatalf("redacted URL = %q", got)
	}
}

func TestEmptySubscriptionCarriesDesktopErrorCode(t *testing.T) {
	_, err := parseSubscriptionBody([]byte(" \n\t"))
	if err == nil {
		t.Fatal("empty subscription was accepted")
	}
	if got := errorCode(err); got != "EMPTY_BODY" {
		t.Fatalf("error code = %q, want EMPTY_BODY", got)
	}
}
