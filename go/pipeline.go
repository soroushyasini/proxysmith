package main

import (
	"encoding/json"
	"fmt"
	"sort"
	"sync"
)

type Candidate struct {
	URI string
	Ms  int64
	Err string
}

func runRound(
	label       string,
	uris        []string,
	concurrency int,
	keepTop     int,
	maxPingMs   int64,
) []Candidate {
	fmt.Printf("\n── %s: testing %d configs (concurrency=%d) ──\n", label, len(uris), concurrency)

	results := make([]Candidate, len(uris))
	sem := make(chan struct{}, concurrency)
	var wg sync.WaitGroup
	var mu sync.Mutex
	done := 0

	for i, uri := range uris {
		wg.Add(1)
		sem <- struct{}{}
		go func(idx int, u string) {
			defer wg.Done()
			defer func() { <-sem }()

			outbound, err := parseURIToOutbound(u)
			if err != nil {
				results[idx] = Candidate{URI: u, Ms: -1, Err: fmt.Sprintf("parse: %v", err)}
				mu.Lock()
				done++
				fmt.Printf("  [%d/%d] SKIP (parse error)\n", done, len(uris))
				mu.Unlock()
				return
			}

			obJSON, _ := json.Marshal(outbound)
			configJSON := fmt.Sprintf(`{"log":{"loglevel":"none"},"outbounds":[%s]}`, string(obJSON))

			ms, err := measureDelay(configJSON, "")
			if err != nil {
				results[idx] = Candidate{URI: u, Ms: -1, Err: err.Error()}
			} else if maxPingMs > 0 && ms > maxPingMs {
				results[idx] = Candidate{URI: u, Ms: -1, Err: fmt.Sprintf("too slow (%dms > %dms)", ms, maxPingMs)}
			} else {
				results[idx] = Candidate{URI: u, Ms: ms}
			}

			mu.Lock()
			done++
			if results[idx].Ms >= 0 {
				fmt.Printf("  [%d/%d] %5dms  %s\n", done, len(uris), results[idx].Ms, shortURI(u, 55))
			} else {
				fmt.Printf("  [%d/%d] FAIL    %s\n", done, len(uris), shortURI(u, 55))
			}
			mu.Unlock()
		}(i, uri)
	}
	wg.Wait()

	// sort passing results by latency
	var passing []Candidate
	for _, r := range results {
		if r.Ms >= 0 {
			passing = append(passing, r)
		}
	}
	sort.Slice(passing, func(i, j int) bool {
		return passing[i].Ms < passing[j].Ms
	})

	if keepTop > 0 && len(passing) > keepTop {
		passing = passing[:keepTop]
	}

	fmt.Printf("  → %d passed, keeping top %d\n", len(passing), len(passing))
	return passing
}

func shortURI(uri string, maxLen int) string {
	// strip fragment
	for i, c := range uri {
		if c == '#' {
			uri = uri[:i]
			break
		}
	}
	if len(uri) > maxLen {
		return uri[:maxLen] + "..."
	}
	return uri
}
