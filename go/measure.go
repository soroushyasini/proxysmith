package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"sort"
	"strings"
	"time"

	xnet "github.com/xtls/xray-core/common/net"
	core "github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
)

type Measurement struct {
	Ms        int64
	JitterMs  int64
	Successes int
	Attempts  int
}

func measureDelay(configJSON, testURL string, attempts int) (Measurement, error) {
	config, err := serial.LoadJSONConfig(strings.NewReader(configJSON))
	if err != nil {
		return Measurement{}, fmt.Errorf("config parse: %w", err)
	}
	config.Inbound = nil
	instance, err := core.New(config)
	if err != nil {
		return Measurement{}, fmt.Errorf("core.New: %w", err)
	}
	if err := instance.Start(); err != nil {
		return Measurement{}, fmt.Errorf("inst.Start: %w", err)
	}
	defer instance.Close()
	if testURL == "" {
		testURL = "https://cp.cloudflare.com/generate_204"
	}
	if attempts < 1 {
		attempts = 1
	}
	transport := &http.Transport{
		DisableKeepAlives:   true,
		TLSHandshakeTimeout: 6 * time.Second,
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			host, portString, err := net.SplitHostPort(address)
			if err != nil {
				return nil, err
			}
			port, err := net.LookupPort(network, portString)
			if err != nil {
				return nil, err
			}
			destination := xnet.TCPDestination(xnet.ParseAddress(host), xnet.Port(port))
			return core.Dial(ctx, instance, destination)
		},
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 12 * time.Second}
	samples := make([]int64, 0, attempts)
	for i := 0; i < attempts; i++ {
		started := time.Now()
		response, err := client.Get(testURL)
		if err != nil {
			continue
		}
		response.Body.Close()
		if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusBadRequest {
			continue
		}
		samples = append(samples, time.Since(started).Milliseconds())
	}
	return summarizeSamples(samples, attempts)
}

func summarizeSamples(samples []int64, attempts int) (Measurement, error) {
	if attempts < 1 {
		return Measurement{}, fmt.Errorf("attempt count must be positive")
	}
	if len(samples) < attempts/2+1 {
		return Measurement{}, fmt.Errorf("only %d of %d attempts succeeded", len(samples), attempts)
	}
	ordered := append([]int64(nil), samples...)
	sort.Slice(ordered, func(i, j int) bool { return ordered[i] < ordered[j] })
	return Measurement{Ms: ordered[len(ordered)/2], JitterMs: ordered[len(ordered)-1] - ordered[0], Successes: len(ordered), Attempts: attempts}, nil
}
