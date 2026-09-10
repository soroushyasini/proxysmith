# Capability map

| Capability | Owner | Independent verification | Release priority |
| --- | --- | --- | --- |
| Subscription ingestion | Go `fetch.go`, Android `SubscriptionFetcher.kt` | Size/status/decode/dedup/sample tests | P0 |
| URI-to-Xray conversion | Go and Kotlin URI parsers | Protocol and malformed-input tests/config validation | P0 |
| Three-round ranking | Go and Kotlin pipelines | Global ranking/median/jitter tests | P0 |
| Cancellation/background execution | Go process lifecycle, Android foreground service | stop/terminal-event tests and Android build | P0 |
| Cross-platform event contract | Dart services and native/Go emitters | event deserialization/service tests | P0 |
| Run configuration | Dart options/settings storage | validation and persistence tests | P1 |
| Pipeline experience | Flutter pipeline screen/widgets | widget, localization, accessibility tests | P1 |
| Source management | Flutter sources screen/storage | validation, refresh, confirm/undo tests | P1 |
| Safe Linux deployment | `bash/proxysmith.sh` | shell syntax and fail-closed inspection | P1 |
| Reproducible build/release | Gradle, scripts, CI, docs | CI matrix and build documentation | P0 |
