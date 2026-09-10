package main

import (
	"bufio"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	DefaultSubURL       = "https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt"
	maxSubscriptionSize = 10 << 20
	maxSubscriptionLine = 64 << 10
)

type subscriptionContents struct {
	URIs        []string
	Duplicates  int
	Unsupported int
}

type codedError struct {
	code string
	err  error
}

func (e *codedError) Error() string { return e.err.Error() }
func (e *codedError) Unwrap() error { return e.err }

func errorWithCode(code, message string, args ...interface{}) error {
	return &codedError{code: code, err: fmt.Errorf(message, args...)}
}

func errorCode(err error) string {
	var coded *codedError
	if errors.As(err, &coded) {
		return coded.code
	}
	return ""
}

func fetchAndSample(subURL string, sampleN, testCount int) ([]string, error) {
	if err := validateHTTPURL(subURL, "subscription URL"); err != nil {
		return nil, err
	}
	if !jsonMode {
		fmt.Printf("  fetching subscription from %s\n", redactURL(subURL))
	}
	client := &http.Client{Timeout: 30 * time.Second}
	body, err := fetchSubscriptionBody(client, subURL, 500*time.Millisecond)
	if err != nil {
		return nil, err
	}
	contents, err := parseSubscriptionBody(body)
	if err != nil {
		return nil, err
	}
	if !jsonMode {
		fmt.Printf("  fetched %d unique supported URIs (%d duplicates, %d unsupported)\n", len(contents.URIs), contents.Duplicates, contents.Unsupported)
	}
	target := len(contents.URIs)
	if sampleN > 1 {
		target = (target + sampleN - 1) / sampleN
	}
	if testCount > 0 && testCount < target {
		target = testCount
	}
	return sampleExactly(contents.URIs, target, rand.New(rand.NewSource(time.Now().UnixNano()))), nil
}

func fetchSubscriptionBody(client *http.Client, subURL string, backoff time.Duration) ([]byte, error) {
	var lastError error
	for attempt := 0; attempt < 3; attempt++ {
		response, err := client.Get(subURL)
		if err != nil {
			lastError = errorWithCode("NETWORK_ERROR", "fetch request failed")
		} else if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
			response.Body.Close()
			lastError = errorWithCode("NETWORK_ERROR", "fetch: unexpected HTTP status %d", response.StatusCode)
		} else {
			body, readErr := io.ReadAll(io.LimitReader(response.Body, maxSubscriptionSize+1))
			response.Body.Close()
			if readErr != nil {
				lastError = errorWithCode("NETWORK_ERROR", "subscription response could not be read")
			} else if len(body) > maxSubscriptionSize {
				return nil, errorWithCode("SUBSCRIPTION_TOO_LARGE", "subscription exceeds %d MiB limit", maxSubscriptionSize>>20)
			} else {
				return body, nil
			}
		}
		if attempt < 2 && backoff > 0 {
			time.Sleep(backoff * time.Duration(1<<attempt))
		}
	}
	return nil, lastError
}

func parseSubscriptionBody(body []byte) (subscriptionContents, error) {
	value := strings.TrimSpace(string(body))
	if value == "" {
		return subscriptionContents{}, errorWithCode("EMPTY_BODY", "subscription returned an empty response")
	}
	if decoded, ok := decodeSubscription(value); ok {
		value = string(decoded)
	}
	result := subscriptionContents{}
	seen := make(map[string]struct{})
	scanner := bufio.NewScanner(strings.NewReader(value))
	scanner.Buffer(make([]byte, 4096), maxSubscriptionLine)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if isValidURI(line) {
			identity := line
			if index := strings.IndexByte(identity, '#'); index >= 0 {
				identity = identity[:index]
			}
			if _, exists := seen[identity]; exists {
				result.Duplicates++
				continue
			}
			seen[identity] = struct{}{}
			result.URIs = append(result.URIs, line)
		} else if hasKnownUnsupportedScheme(line) {
			result.Unsupported++
		}
	}
	if err := scanner.Err(); err != nil {
		return subscriptionContents{}, errorWithCode("SUBSCRIPTION_TOO_LARGE", "subscription line exceeds %d KiB limit", maxSubscriptionLine>>10)
	}
	if len(result.URIs) == 0 {
		return subscriptionContents{}, errorWithCode("NO_VALID_SCHEMES", "subscription returned no supported proxy URIs")
	}
	return result, nil
}

func decodeSubscription(value string) ([]byte, bool) {
	for _, encoding := range []*base64.Encoding{base64.StdEncoding, base64.RawStdEncoding, base64.URLEncoding, base64.RawURLEncoding} {
		if decoded, err := encoding.DecodeString(value); err == nil && strings.Contains(string(decoded), "://") {
			return decoded, true
		}
	}
	return nil, false
}

func sampleExactly(input []string, count int, rng *rand.Rand) []string {
	if count <= 0 || len(input) == 0 {
		return nil
	}
	if count >= len(input) {
		return append([]string(nil), input...)
	}
	indices := rng.Perm(len(input))[:count]
	result := make([]string, count)
	for i, index := range indices {
		result[i] = input[index]
	}
	return result
}

func validateHTTPURL(raw, label string) error {
	u, err := url.ParseRequestURI(strings.TrimSpace(raw))
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
		return fmt.Errorf("%s must be an absolute HTTP or HTTPS URL", label)
	}
	return nil
}

func redactURL(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return "<invalid URL>"
	}
	u.User = nil
	u.RawQuery = ""
	u.Fragment = ""
	return u.String()
}

func isValidURI(value string) bool {
	lower := strings.ToLower(value)
	for _, prefix := range []string{"vless://", "vmess://", "trojan://", "ss://", "hysteria2://", "hy2://"} {
		if strings.HasPrefix(lower, prefix) {
			return true
		}
	}
	return false
}

func hasKnownUnsupportedScheme(value string) bool {
	return strings.HasPrefix(strings.ToLower(value), "tuic://")
}
