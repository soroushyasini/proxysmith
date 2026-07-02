package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"
)

type Config struct {
	SubURL       string
	SampleN      int
	Concurrency  int
	MaxPingMs    int64
	TestCount    int
	OutputFormat string
}

func parseFlags() Config {
	subURL := flag.String("sub-url", DefaultSubURL, "Subscription URL")
	sampleN := flag.Int("sample-n", 5, "Sample rate (1-in-N, 1=no sampling)")
	concurrency := flag.Int("concurrency", 20, "Round 1 concurrency (1-60)")
	maxPingMs := flag.Int64("max-ping-ms", 8000, "Max ping ms (0=no limit)")
	testCount := flag.Int("test-count", 350, "Target number of configs to test")
	outputFormat := flag.String("output-format", "human", "Output format: human | jsonl")
	flag.Parse()

	c := Config{
		SubURL:       *subURL,
		SampleN:      *sampleN,
		Concurrency:  *concurrency,
		MaxPingMs:    *maxPingMs,
		TestCount:    *testCount,
		OutputFormat: *outputFormat,
	}
	if c.SampleN < 1 {
		c.SampleN = 1
	}
	if c.Concurrency < 1 {
		c.Concurrency = 1
	}
	if c.Concurrency > 60 {
		c.Concurrency = 60
	}
	return c
}

var jsonMode bool

// realStdout holds the original stdout handle, captured before os.Stdout
// gets redirected to null. All our own JSON output goes through this,
// never through the (possibly redirected) os.Stdout variable.
var realStdout *os.File = os.Stdout

func emit(event map[string]interface{}) {
	if !jsonMode {
		return
	}
	b, err := json.Marshal(event)
	if err != nil {
		return
	}
	fmt.Fprintln(realStdout, string(b))
}

func emitStatus(message string) {
	emit(map[string]interface{}{"type": "status", "message": message})
}

func emitError(message string) {
	emit(map[string]interface{}{"type": "error", "message": message})
}

// silenceStdout redirects the package-level os.Stdout to the null device.
// Any library that prints via fmt.Println/fmt.Fprintln(os.Stdout, ...) —
// including xray-core's deprecation warnings, which ignore the configured
// log level — gets swallowed. Our own output uses realStdout instead, so
// it's unaffected. Must be called before pipeline execution starts, after
// realStdout has already captured the original handle above.
func silenceStdout() {
	devNull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		return // if this fails, worst case is noisier jsonl output, not a crash
	}
	os.Stdout = devNull
}

func main() {
	cfg := parseFlags()
	jsonMode = cfg.OutputFormat == "jsonl"

	if jsonMode {
		silenceStdout()
	} else {
		fmt.Println()
		fmt.Println("── ProxySmith Pipeline ──")
		fmt.Println()
	}

	emitStatus("fetching subscription")
	uris, err := fetchAndSample(cfg.SubURL, cfg.SampleN)
	if err != nil {
		if jsonMode {
			emitError(fmt.Sprintf("fetch failed: %v", err))
		} else {
			fmt.Printf("FAILED: %v\n", err)
		}
		os.Exit(1)
	}

	if cfg.TestCount > 0 && len(uris) > cfg.TestCount {
		uris = uris[:cfg.TestCount]
	}
	emit(map[string]interface{}{"type": "fetched", "count": len(uris)})

	start := time.Now()

	r1 := runRound(1, "Round 1", uris, cfg.Concurrency, 60, cfg.MaxPingMs)
	if len(r1) == 0 {
		failNoPassing(1)
	}

	r1uris := extractURIs(r1)
	r2 := runRound(2, "Round 2", r1uris, 5, 30, 0)
	if len(r2) == 0 {
		failNoPassing(2)
	}

	r2uris := extractURIs(r2)
	r3 := runRound(3, "Round 3", r2uris, 1, 10, 0)
	if len(r3) == 0 {
		failNoPassing(3)
	}

	elapsed := time.Since(start)

	if jsonMode {
		for i, c := range r3 {
			emit(map[string]interface{}{
				"type": "result",
				"rank": i + 1,
				"ms":   c.Ms,
				"uri":  c.URI,
			})
		}
		emit(map[string]interface{}{"type": "done", "count": len(r3)})
	} else {
		fmt.Printf("\n════════════════════════════════════════\n")
		fmt.Printf("  FINAL RESULTS  (%s total)\n", elapsed.Round(time.Second))
		fmt.Printf("════════════════════════════════════════\n\n")
		for i, c := range r3 {
			fmt.Printf("  #%02d  %5dms  %s\n", i+1, c.Ms, shortURI(c.URI, 70))
		}

		outFile := "results.txt"
		if f, err := os.Create(outFile); err == nil {
			for _, c := range r3 {
				fmt.Fprintf(f, "%s\n", c.URI)
			}
			f.Close()
			fmt.Printf("\n  URIs saved to %s\n", outFile)
		}

		outFile2 := "results_with_ping.txt"
		if f2, err := os.Create(outFile2); err == nil {
			for _, c := range r3 {
				fmt.Fprintf(f2, "%dms\t%s\n", c.Ms, c.URI)
			}
			f2.Close()
			fmt.Printf("  URIs+ping saved to %s\n\n", outFile2)
		}
	}
}

func failNoPassing(round int) {
	msg := fmt.Sprintf("no configs passed round %d", round)
	if jsonMode {
		emitError(msg)
	} else {
		fmt.Println(msg + ". Try increasing max ping or lowering sample rate.")
	}
	os.Exit(1)
}

func extractURIs(cs []Candidate) []string {
	uris := make([]string, len(cs))
	for i, c := range cs {
		uris[i] = c.URI
	}
	return uris
}