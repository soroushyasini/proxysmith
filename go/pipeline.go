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
	roundNum int,
	label string,
	uris []string,
	concurrency int,
	keepTop int,
	maxPingMs int64,
) []Candidate {
	if !jsonMode {
		fmt.Printf("\n── %s: testing %d configs (concurrency=%d) ──\n", label, len(uris), concurrency)
	}

	results := make([]Candidate, len(uris))
	sem := make(chan struct{}, concurrency)
	var wg sync.WaitGroup
	var mu sync.Mutex
	done := 0
	total := len(uris)

	for i, uri := range uris {
		wg.Add(1)
		sem <- struct{}{}
		go func(idx int, u string) {
			defer wg.Done()
			defer func() { <-sem }()

			outbound, err := parseURIToOutbound(u)
			if err != nil {
				results[idx] = Candidate{URI: u, Ms: -1, Err: fmt.Sprintf("parse: %v", err)}
				reportDone(&mu, &done, total, roundNum, results[idx], u)
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

			reportDone(&mu, &done, total, roundNum, results[idx], u)
		}(i, uri)
	}
	wg.Wait()

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

	if !jsonMode {
		fmt.Printf("  → %d passed, keeping top %d\n", len(passing), len(passing))
	}
	return passing
}

// reportDone is called under mu from each worker goroutine on completion —
// mu already serializes access here, so JSON lines never interleave.
func reportDone(mu *sync.Mutex, done *int, total int, roundNum int, result Candidate, uri string) {
	mu.Lock()
	defer mu.Unlock()
	*done++
	d := *done

	if jsonMode {
		emit(map[string]interface{}{
			"type":  "progress",
			"round": roundNum,
			"done":  d,
			"total": total,
		})
		return
	}

	if result.Ms >= 0 {
		fmt.Printf("  [%d/%d] %5dms  %s\n", d, total, result.Ms, shortURI(uri, 55))
	} else {
		fmt.Printf("  [%d/%d] FAIL    %s\n", d, total, shortURI(uri, 55))
	}
}
func shortURI(uri string, maxLen int) string {
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