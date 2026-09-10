package main

import (
	"strings"
	"testing"
	"time"
)

func TestConfigRejectsConcurrencyOutsideContract(t *testing.T) {
	base := Config{
		SubURL:       "https://example.com/subscription",
		SampleN:      1,
		Concurrency:  20,
		MaxPingMs:    8_000,
		TestCount:    350,
		TestURL:      "https://example.com/generate_204",
		OutputFormat: "jsonl",
	}
	for _, concurrency := range []int{0, 61} {
		config := base
		config.Concurrency = concurrency
		if err := validateConfig(config); err == nil || !strings.Contains(err.Error(), "concurrency") {
			t.Fatalf("concurrency %d validation error = %v", concurrency, err)
		}
	}
}

func TestReadStdinOptionsReadsBothPrivateURLs(t *testing.T) {
	config := Config{SubURLStdin: true, TestURLStdin: true}
	got, err := readStdinOptions(
		config,
		strings.NewReader("https://example.com/sub?token=private\nhttps://example.com/probe?token=private\n"),
	)
	if err != nil {
		t.Fatalf("readStdinOptions returned error: %v", err)
	}
	if got.SubURL != "https://example.com/sub?token=private" || got.TestURL != "https://example.com/probe?token=private" {
		t.Fatalf("stdin options = %#v", got)
	}
}

func TestProgressReportingIsThrottledButFinalUpdateIsKept(t *testing.T) {
	last := time.Unix(100, 0)
	if shouldReportProgress(2, 10, last.Add(50*time.Millisecond), last) {
		t.Fatal("intermediate update inside throttle window was reported")
	}
	if !shouldReportProgress(3, 10, last.Add(100*time.Millisecond), last) {
		t.Fatal("intermediate update at throttle boundary was dropped")
	}
	if !shouldReportProgress(10, 10, last.Add(time.Millisecond), last) {
		t.Fatal("final update was dropped")
	}
}

func TestSummarizeSamplesUsesMedianAndRangeJitter(t *testing.T) {
	measurement, err := summarizeSamples([]int64{120, 80, 100}, 3)
	if err != nil {
		t.Fatalf("summarizeSamples returned error: %v", err)
	}
	if measurement.Ms != 100 || measurement.JitterMs != 40 || measurement.Successes != 3 || measurement.Attempts != 3 {
		t.Fatalf("unexpected measurement: %#v", measurement)
	}
}

func TestSummarizeSamplesRequiresMajoritySuccess(t *testing.T) {
	if _, err := summarizeSamples([]int64{75}, 3); err == nil {
		t.Fatal("one success out of three was accepted")
	}
}

func TestRankCandidatesUsesAllCandidatesAndStableQualityOrder(t *testing.T) {
	input := []Candidate{
		{URI: "first-completed", Ms: 90, JitterMs: 30, Successes: 3, Attempts: 3, InputIndex: 0},
		{URI: "fast-but-flaky", Ms: 20, JitterMs: 5, Successes: 2, Attempts: 3, InputIndex: 1},
		{URI: "best", Ms: 70, JitterMs: 10, Successes: 3, Attempts: 3, InputIndex: 2},
		{URI: "same-latency-more-jitter", Ms: 70, JitterMs: 20, Successes: 3, Attempts: 3, InputIndex: 3},
	}

	got := rankCandidates(input, 2)
	if len(got) != 2 || got[0].URI != "best" || got[1].URI != "same-latency-more-jitter" {
		t.Fatalf("ranked candidates = %#v", got)
	}
}
