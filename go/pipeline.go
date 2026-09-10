package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"sort"
	"strings"
	"sync"
	"time"
)

type Candidate struct {
	URI        string
	Ms         int64
	JitterMs   int64
	Successes  int
	Attempts   int
	InputIndex int
	Err        string
}

func runRound(roundNum int, label string, uris []string, concurrency, keepTop int, maxPingMs int64, testURL string) []Candidate {
	if !jsonMode {
		fmt.Printf("\n── %s: testing %d configs (concurrency=%d) ──\n", label, len(uris), concurrency)
	}
	if concurrency < 1 {
		concurrency = 1
	}
	results := make([]Candidate, len(uris))
	jobs := make(chan int)
	var workers sync.WaitGroup
	var progressMu sync.Mutex
	done := 0
	lastProgressAt := time.Time{}
	attempts := roundNum
	if attempts > 3 {
		attempts = 3
	}
	worker := func() {
		defer workers.Done()
		for index := range jobs {
			uri := uris[index]
			candidate := Candidate{URI: uri, Ms: -1, InputIndex: index, Attempts: attempts}
			outbound, err := parseURIToOutbound(uri)
			if err != nil {
				candidate.Err = fmt.Sprintf("parse: %v", err)
			} else if outboundJSON, err := json.Marshal(outbound); err != nil {
				candidate.Err = fmt.Sprintf("marshal: %v", err)
			} else {
				configJSON := fmt.Sprintf(`{"log":{"loglevel":"none"},"outbounds":[%s]}`, outboundJSON)
				measurement, err := measureDelay(configJSON, testURL, attempts)
				if err != nil {
					candidate.Err = err.Error()
				} else if maxPingMs > 0 && measurement.Ms > maxPingMs {
					candidate.Err = fmt.Sprintf("too slow (%dms > %dms)", measurement.Ms, maxPingMs)
				} else {
					candidate.Ms = measurement.Ms
					candidate.JitterMs = measurement.JitterMs
					candidate.Successes = measurement.Successes
					candidate.Attempts = measurement.Attempts
				}
			}
			results[index] = candidate
			reportDone(&progressMu, &done, &lastProgressAt, len(uris), roundNum, candidate, uri)
		}
	}
	workerCount := concurrency
	if workerCount > len(uris) {
		workerCount = len(uris)
	}
	workers.Add(workerCount)
	for i := 0; i < workerCount; i++ {
		go worker()
	}
	for index := range uris {
		jobs <- index
	}
	close(jobs)
	workers.Wait()
	passing := make([]Candidate, 0, len(results))
	for _, result := range results {
		if result.Ms >= 0 {
			passing = append(passing, result)
		}
	}
	passing = rankCandidates(passing, keepTop)
	if !jsonMode {
		fmt.Printf("  → %d passed, keeping top %d\n", len(passing), len(passing))
	}
	return passing
}

func rankCandidates(input []Candidate, keepTop int) []Candidate {
	result := append([]Candidate(nil), input...)
	sort.SliceStable(result, func(i, j int) bool {
		left, right := result[i], result[j]
		leftQuality := left.Successes * right.Attempts
		rightQuality := right.Successes * left.Attempts
		if leftQuality != rightQuality {
			return leftQuality > rightQuality
		}
		if left.Ms != right.Ms {
			return left.Ms < right.Ms
		}
		if left.JitterMs != right.JitterMs {
			return left.JitterMs < right.JitterMs
		}
		return left.InputIndex < right.InputIndex
	})
	if keepTop > 0 && len(result) > keepTop {
		result = result[:keepTop]
	}
	return result
}

func reportDone(mu *sync.Mutex, done *int, lastProgressAt *time.Time, total, roundNum int, result Candidate, uri string) {
	mu.Lock()
	defer mu.Unlock()
	*done = *done + 1
	if jsonMode {
		now := time.Now()
		if !shouldReportProgress(*done, total, now, *lastProgressAt) {
			return
		}
		*lastProgressAt = now
		emit(map[string]interface{}{"type": "progress", "round": roundNum, "done": *done, "total": total})
		return
	}
	if result.Ms >= 0 {
		fmt.Printf("  [%d/%d] %5dms  %s\n", *done, total, result.Ms, shortURI(uri, 55))
	} else {
		fmt.Printf("  [%d/%d] FAIL    %s\n", *done, total, shortURI(uri, 55))
	}
}

func shouldReportProgress(done, total int, now, last time.Time) bool {
	return done >= total || last.IsZero() || now.Sub(last) >= 100*time.Millisecond
}

func shortURI(uri string, maxLen int) string {
	if index := strings.IndexByte(uri, '#'); index >= 0 {
		uri = uri[:index]
	}
	parsed, err := url.Parse(uri)
	if err != nil || parsed.Scheme == "" {
		return "<redacted proxy URI>"
	}
	if parsed.Scheme == "vmess" || parsed.Host == "" {
		return parsed.Scheme + "://<redacted>"
	}
	return parsed.Scheme + "://" + parsed.Host
}
