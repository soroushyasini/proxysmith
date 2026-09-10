# Specification: pipeline hardening and UX refresh

## Goal

Make ProxySmith reliable enough to build as the next minor release: unbiased selection, robust parsing/fetching, consistent platform behavior, visible quality metrics, safe background execution, and a more accessible configurable UI.

## Backend contract

`PipelineOptions` contains:

- `subUrl`: required HTTP(S) URL.
- `testCount`: 50-5000 in the UI and 1-5000 at backend boundaries.
- `maxPingMs`: 500-15000 in the UI; `0` disables the CLI cutoff.
- `concurrency`: 1-60.
- `testUrl`: required HTTP(S) URL.

Final result events retain `rank`, `ms`, and `uri`, and add `jitterMs`, `successes`, and `attempts`. Done events retain `count` and add `elapsedMs`. Unknown additive fields are ignored by old consumers.

## Acceptance criteria

1. A subscription with duplicates yields a stable unique pool before sampling.
2. A request for N configurations yields exactly `min(N, uniqueValidCount)` entries with unbiased Fisher-Yates selection.
3. Malformed SS, missing user info, host, or port returns a parse error without panic/crash.
4. VLESS/VMess/Trojan WebSocket, gRPC, HTTP/2 aliases, and Hysteria2 generate Xray-compatible outbound JSON for the pinned engine.
5. TUIC entries are excluded as unsupported and the fetched summary reports exclusions.
6. Every candidate in a round is measured before the global top K is selected.
7. Final results show median latency, jitter, and success ratio and remain sorted by quality.
8. Desktop passes subscription and test URLs through stdin, drains both child streams, and emits at most one terminal error.
9. Android starts a user-initiated data-sync foreground service for a run and stops it for success, error, cancellation, or activity teardown.
10. Custom URLs show inline corrective errors and cannot start a run while invalid.
11. App preferences restore across launches without storing proxy results.
12. Returning from source management refreshes the source picker; delete includes confirmation and undo.
13. Controls meet Flutter's 48-pixel accessibility target and core widget tests exercise English and Persian layouts.
14. CI enforces Go tests/vet, Flutter analyze/test, Kotlin unit tests, a debug Android build, and Bash syntax.

## Source-backed compatibility decisions

- Xray v1.260327.0 registers Hysteria (not TUIC) and uses `network` in stream settings: https://github.com/XTLS/Xray-core/blob/v1.260327.0/infra/conf/xray.go and https://github.com/XTLS/Xray-core/blob/v1.260327.0/infra/conf/transport_internet.go
- Hysteria2 uses protocol `hysteria`, version/address/port settings, and Hysteria transport auth: https://github.com/XTLS/Xray-core/blob/v1.260327.0/infra/conf/hysteria.go and https://xtls.github.io/en/config/transports/hysteria.html
- Android foreground data transfer uses the `dataSync` type and permission: https://developer.android.com/develop/background-work/services/fgs/service-types
- Flutter recommends at least 48x48 logical pixels for Android tap targets: https://docs.flutter.dev/ui/accessibility/ui-design-and-styling
- `Process.start` provides stdin and requires draining stdout/stderr: https://api.dart.dev/dart-io/Process/start.html
