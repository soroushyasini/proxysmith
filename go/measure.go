package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"

	core "github.com/xtls/xray-core/core"
	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/infra/conf/serial"
)

func measureDelay(configJSON string, testURL string) (int64, error) {
	config, err := serial.LoadJSONConfig(strings.NewReader(configJSON))
	if err != nil {
		return -1, fmt.Errorf("config parse: %w", err)
	}
	config.Inbound = nil

	inst, err := core.New(config)
	if err != nil {
		return -1, fmt.Errorf("core.New: %w", err)
	}
	if err := inst.Start(); err != nil {
		return -1, fmt.Errorf("inst.Start: %w", err)
	}
	defer inst.Close()

	if testURL == "" {
		testURL = "https://www.google.com/generate_204"
	}

	tr := &http.Transport{
		TLSHandshakeTimeout: 6 * time.Second,
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			host, portStr, err := net.SplitHostPort(addr)
			if err != nil {
				return nil, err
			}
			port, err := net.LookupPort(network, portStr)
			if err != nil {
				return nil, err
			}
			dest := xnet.TCPDestination(
				xnet.ParseAddress(host),
				xnet.Port(port),
			)
			return core.Dial(ctx, inst, dest)
		},
	}
	client := &http.Client{Transport: tr, Timeout: 12 * time.Second}

	var best int64 = -1
	for i := 0; i < 2; i++ {
		start := time.Now()
		resp, err := client.Get(testURL)
		if err != nil {
			continue
		}
		resp.Body.Close()
		ms := time.Since(start).Milliseconds()
		if best < 0 || ms < best {
			best = ms
		}
	}
	if best < 0 {
		return -1, fmt.Errorf("all attempts failed")
	}
	return best, nil
}
