# Backend-first implementation plan

1. Establish contracts and regression tests for ingestion, parsers, ranking, events, settings, and URL validation.
2. Harden the Go backend: bounded fetch, exact sampling, parser fixes, protocol alignment, bounded workers, progressive measurements, cancellation, stdin secrets, and structured summaries.
3. Align Android: exact sampling/dedup, global ranking, progressive metrics, Hysteria2 correction/TUIC rejection, bounded fetch/retries, option validation, and foreground-service lifetime.
4. Harden the Linux workflow: scoped subscription cleanup, validated numeric input, private temporary directory, exact final top 10, fail-closed config validation, and deployment rollback.
5. Upgrade the Flutter contract and experience: options model, settings persistence, endpoint/concurrency/latency controls, actionable validation, metrics, refreshed sources, safe deletion, semantic version checks, localization, responsiveness, and accessibility.
6. Make builds reproducible: Gradle correction, ABI/build script alignment, ignore/LFS fixes, CI, license, changelog, and accurate build docs.
7. Run formatters and all locally available tests/build checks; inspect staged content for secrets/trash; remove confirmed generated artifacts; review the diff on correctness, simplicity, architecture, security, and performance.
8. Commit once after the complete verified set, then push the current branch as requested.
