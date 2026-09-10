# ProxySmith engineering constraints

These constraints are the release gate for the pipeline hardening and UX work.

## Product behavior

- Fetch HTTP(S) subscriptions, decode base64 or plain-text lists, normalize and de-duplicate entries, then select exactly the requested number when enough valid entries exist.
- Rank every candidate that entered a round before taking the global top 60, 30, and 10. Completion order must never influence ranking.
- Rank final results by reliability, then median latency, lower jitter, and stable input order.
- Support only configurations the bundled Xray engine can represent: VLESS, VMess, Trojan, Shadowsocks, and Hysteria2. TUIC must be rejected explicitly rather than accepted and failed later.
- Preserve the existing `PSJSON:` desktop event prefix and existing event fields. New fields must be additive.
- A stopped run must terminate work and must not produce a second fatal-error message.

## Security and resilience

- Accept only `http` and `https` subscription/test URLs with a host.
- Keep private subscription and test URLs out of desktop process arguments and normal logs. Redact credentials and query strings in human-facing diagnostics.
- Cap subscription responses at 10 MiB and individual decoded lines at 64 KiB.
- Bound concurrent tests to 1-60 and reject invalid numeric settings at boundaries.
- Never execute downloaded scripts or binaries automatically. Deployment must stop on validation failure and restore the previous config if service restart fails.

## Performance

- Use bounded worker pools; do not create one unbounded task per subscription entry.
- Default round concurrency is 20 across platforms; user-selected concurrency is capped at 60.
- Use progressively stronger measurement: one attempt in round 1, two in round 2, and three in round 3. Report median latency, jitter, and successful attempt count.
- Throttle progress events while always delivering the final event for a round.

## UI and accessibility

- Validate custom subscription and test URLs before starting.
- Persist theme, language, source, test count, latency limit, concurrency, and test endpoint; never persist tested proxy credentials or result history.
- Source edits must refresh the pipeline picker. Deletion must require confirmation and offer undo.
- All icon/button targets must be at least 48 logical pixels and carry meaningful labels/tooltips.
- Loading, empty, warning, error, stopped, and successful states must remain visible and localized in English and Persian.

## Quality gates

- `go test ./...` and `go vet ./...` pass on Go 1.26.
- `flutter analyze` and `flutter test` pass from `app/`.
- Android unit tests and a debug APK build pass in CI.
- Shell syntax validation passes for Bash scripts.
- The staged diff contains no secrets, IDE/cache files, generated binaries, build output, or release archives.

## Explicitly deferred

- Hard-kill isolation for a JNI call that hangs inside libv2ray requires moving measurements to a dedicated Android process and a versioned IPC protocol. The foreground service and total pipeline timeout improve normal background reliability but cannot preempt native code that never returns.
- Scheduled health checks, long-term result history, throughput testing, and multi-source aggregation need separate product/privacy decisions and are not silently enabled in this release.
