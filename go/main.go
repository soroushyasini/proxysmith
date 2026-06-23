package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	SubURL      string
	SampleN     int
	Concurrency int
	MaxPingMs   int64
}

func promptConfig() Config {
	r := bufio.NewReader(os.Stdin)

	ask := func(prompt, def string) string {
		fmt.Printf("  %s [default: %s]: ", prompt, def)
		line, _ := r.ReadString('\n')
		line = strings.TrimSpace(line)
		if line == "" {
			return def
		}
		return line
	}

	fmt.Println()
	fmt.Println("── ProxySmith Pipeline Config ──")
	fmt.Println()

	subURL   := ask("Subscription URL", DefaultSubURL)
	sampleS  := ask("Sample rate (1-in-N, 1=no sampling, 5=pick 1 of every 5)", "5")
	concurrS := ask("Round 1 concurrency (20-60)", "20")
	pingS    := ask("Max ping ms (0=no limit)", "8000")

	sampleN, _  := strconv.Atoi(sampleS)
	concurr, _  := strconv.Atoi(concurrS)
	pingMs, _   := strconv.ParseInt(pingS, 10, 64)

	if sampleN < 1  { sampleN = 1 }
	if concurr < 1  { concurr = 20 }
	if concurr > 60 { concurr = 60 }

	return Config{
		SubURL:      subURL,
		SampleN:     sampleN,
		Concurrency: concurr,
		MaxPingMs:   pingMs,
	}
}

func main() {
	cfg := promptConfig()

	fmt.Println()
	fmt.Println("── Step 1: Fetch & Sample ──")
	uris, err := fetchAndSample(cfg.SubURL, cfg.SampleN)
	if err != nil {
		fmt.Printf("FAILED: %v\n", err)
		os.Exit(1)
	}

	start := time.Now()

	// Round 1: full concurrency, keep top 60
	r1 := runRound("Round 1", uris, cfg.Concurrency, 60, cfg.MaxPingMs)
	if len(r1) == 0 {
		fmt.Println("No configs passed Round 1. Try increasing max ping or lowering sample rate.")
		os.Exit(1)
	}

	// Round 2: concurrency 5, keep top 30
	r1uris := extractURIs(r1)
	r2 := runRound("Round 2", r1uris, 5, 30, 0)
	if len(r2) == 0 {
		fmt.Println("No configs passed Round 2.")
		os.Exit(1)
	}

	// Round 3: single-threaded, keep top 10
	r2uris := extractURIs(r2)
	r3 := runRound("Round 3", r2uris, 1, 10, 0)
	if len(r3) == 0 {
		fmt.Println("No configs passed Round 3.")
		os.Exit(1)
	}

	elapsed := time.Since(start)

	// ── Final output ──────────────────────────────────────────────────────────
	fmt.Printf("\n════════════════════════════════════════\n")
	fmt.Printf("  FINAL RESULTS  (%s total)\n", elapsed.Round(time.Second))
	fmt.Printf("════════════════════════════════════════\n\n")

	for i, c := range r3 {
		fmt.Printf("  #%02d  %5dms  %s\n", i+1, c.Ms, shortURI(c.URI, 70))
	}

	// save plain URI list
	outFile := "results.txt"
	f, err := os.Create(outFile)
	if err == nil {
		for _, c := range r3 {
			fmt.Fprintf(f, "%s\n", c.URI)
		}
		f.Close()
		fmt.Printf("\n  URIs saved to %s\n", outFile)
	}

	// save with latencies
	outFile2 := "results_with_ping.txt"
	f2, err := os.Create(outFile2)
	if err == nil {
		for _, c := range r3 {
			fmt.Fprintf(f2, "%dms\t%s\n", c.Ms, c.URI)
		}
		f2.Close()
		fmt.Printf("  URIs+ping saved to %s\n\n", outFile2)
	}
}

func extractURIs(cs []Candidate) []string {
	uris := make([]string, len(cs))
	for i, c := range cs {
		uris[i] = c.URI
	}
	return uris
}
