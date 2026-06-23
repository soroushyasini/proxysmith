package main

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"strings"
	"time"
)

const DefaultSubURL = "https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt"

func fetchAndSample(subURL string, sampleN int) ([]string, error) {
	fmt.Printf("  fetching subscription from %s\n", subURL)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Get(subURL)
	if err != nil {
		return nil, fmt.Errorf("fetch: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read: %w", err)
	}

	// try base64 decode; if it fails treat as plain text
	var lines []string
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(string(body)))
	if err != nil {
		decoded, err = base64.RawStdEncoding.DecodeString(strings.TrimSpace(string(body)))
	}
	if err == nil {
		// decoded successfully
		scanner := bufio.NewScanner(strings.NewReader(string(decoded)))
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if isValidURI(line) {
				lines = append(lines, line)
			}
		}
	} else {
		// plain text subscription
		scanner := bufio.NewScanner(strings.NewReader(string(body)))
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if isValidURI(line) {
				lines = append(lines, line)
			}
		}
	}

	fmt.Printf("  fetched %d valid URIs\n", len(lines))

	if sampleN <= 1 {
		return lines, nil
	}

	// sample 1-in-N: pick indices 0, N, 2N, ... then shuffle within each bucket
	var sampled []string
	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	for i := 0; i < len(lines); i += sampleN {
		end := i + sampleN
		if end > len(lines) {
			end = len(lines)
		}
		bucket := lines[i:end]
		pick := bucket[rng.Intn(len(bucket))]
		sampled = append(sampled, pick)
	}

	fmt.Printf("  after sampling (1-in-%d): %d URIs\n", sampleN, len(sampled))
	return sampled, nil
}

func isValidURI(s string) bool {
	for _, prefix := range []string{"vless://", "vmess://", "trojan://", "ss://", "tuic://", "hysteria2://", "hy2://"} {
		if strings.HasPrefix(s, prefix) {
			return true
		}
	}
	return false
}
