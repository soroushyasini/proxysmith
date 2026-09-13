# ProxySmith

ProxySmith downloads a proxy subscription, tests each supported configuration through a real Xray core, and returns the ten most reliable low-latency results. It includes an Android/Windows/Linux Flutter app, a Go pipeline used by desktop builds, and a fail-closed Linux server generator.

## What changed in 2.4

- Candidates are selected without first-completion or first-in-feed bias.
- Final ranking considers success rate, median latency, and jitter.
- Downloads are limited to 10 MiB, URLs are validated, duplicates are removed, and exact sample sizes are used.
- Desktop subscription and test URLs travel over standard input instead of appearing in process lists.
- Android uses a foreground service during a run and supports API 24 or newer.
- Theme, language, source, count, latency limit, concurrency, and test endpoint preferences persist locally.
- Results expose reliability and jitter and can be copied, selected, or displayed as QR codes.
- Source editing validates URLs and supports confirmed deletion with undo.
- CI checks Go, Flutter, Android, shell, and PowerShell code.

See [CHANGELOG.md](CHANGELOG.md), [CONSTRAINTS.md](CONSTRAINTS.md), and [docs/CAPABILITY-MAP.md](docs/CAPABILITY-MAP.md) for the release contract and implementation boundaries.

## Pipeline

1. Fetch up to 10 MiB from an absolute HTTP(S) subscription URL.
2. Decode plain-text or base64 content, retain supported schemes, and deduplicate links without their display fragments.
3. Select the exact requested sample uniformly.
4. Test every Round 1 candidate, rank globally, and retain 60.
5. Re-test all survivors twice and retain 30.
6. Re-test all survivors three times and retain 10.

Candidates are ranked by successful-attempt ratio, median latency, jitter range, and original order. A majority of attempts must succeed.

## Supported links

| Protocol | Transports |
| --- | --- |
| VLESS | TCP, WebSocket, gRPC, XHTTP, HTTPUpgrade; none, TLS, Reality |
| VMess | TCP, WebSocket, gRPC, XHTTP, HTTPUpgrade; none, TLS |
| Trojan | TCP, WebSocket, gRPC, XHTTP, HTTPUpgrade; TLS |
| Shadowsocks | TCP; SIP002 userinfo and full-base64 forms |
| Hysteria2 / HY2 | Xray Hysteria v2 transport |

TUIC is deliberately rejected because the pinned Xray core does not provide a TUIC outbound. HTTP/2 share-link transports are also rejected because the pinned Xray version removed the legacy `h2` transport name; use XHTTP where available.

## Flutter app

Requirements:

- A current stable Flutter SDK compatible with Dart 3.12
- Android Studio/SDK for Android builds
- Android 7.0 (API 24) or newer for installed APKs
- Windows or Linux development dependencies for desktop builds
- Git LFS to retrieve `app/android/app/libs/libv2ray.aar`

Prepare and verify:

```text
git lfs pull
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

The checked-in AAR contains ARMv7 and ARM64 native libraries. Release signing is used when `app/android/key.properties` provides `keyAlias`, `keyPassword`, `storeFile`, and `storePassword`; without that local file, Gradle can still compile debug builds.

### Android release packages

From PowerShell with Flutter in `PATH`:

```powershell
cd app
.\build_all.ps1
```

The script runs dependency resolution, analysis, and tests before producing ARMv7, ARM64, and universal APKs plus a Google Play App Bundle under `app/release/`. `SHA256SUMS.txt` is generated alongside them. The release directory and signing material are ignored by Git.

Kotlin compilation is intentionally non-incremental and in-process because this Windows checkout and the Flutter package cache live on different drives. This avoids the cross-volume cache failure during a normal `flutter build` invocation.

### Desktop builds

Build the matching Go helper first:

```text
cd go
go build -trimpath -o ../app/windows/bin/proxysmith-pipeline-windows-amd64.exe .
```

On Linux, name the output `app/linux/bin/proxysmith-pipeline-linux-amd64`. Then build Flutter and bundle the helper:

```powershell
cd app
flutter build windows --release
cd ..
.\scripts\bundle_desktop_binaries.ps1
```

```bash
cd app
flutter build linux --release
cd ..
./scripts/bundle_desktop_binaries.sh
```

The desktop app validates options before launch, drains both child-process streams, prevents overlapping runs, and passes potentially sensitive subscription and test URLs over standard input.

## Go CLI

The Go module requires Go 1.26 and pins `github.com/xtls/xray-core` to `v1.260327.0`.

```text
cd go
go test ./...
go vet ./...
go build -trimpath -o proxysmith .
./proxysmith --sub-url https://example.com/subscription --test-count 350
```

Useful options:

```text
--sample-n 1
--concurrency 20
--max-ping-ms 5000
--test-url https://cp.cloudflare.com/generate_204
--output-format human|jsonl
--sub-url-stdin
--test-url-stdin
```

`--sub-url-stdin` reads the subscription URL from standard input. When `--test-url-stdin` is also set, the test URL is read from the following line. The desktop app uses both flags so private URL data never appears in process arguments. JSON mode emits `PSJSON:`-prefixed `status`, `fetched`, `progress`, `result`, `done`, and `error` records. Result records include `ms`, `jitterMs`, `successes`, and `attempts`; done records include `elapsedMs`.

Always compile the whole package (`go build .` or `go run .`), because `register.go` activates Xray protocols and transports through package initialization.

## Linux server generator

`bash/proxysmith.sh` requires `xray-knife`, `xray`, and `python3`. It never downloads or installs executables. Install those tools from sources you trust, then run:

```bash
bash bash/proxysmith.sh
bash bash/proxysmith.sh --deploy
```

The script:

- touches only the subscription whose remark is `proxysmith-daily`;
- uses a private unpredictable temporary directory;
- validates numeric input before it reaches embedded code;
- deduplicates complete credentials rather than collapsing all accounts on an endpoint;
- produces exactly ten final configurations;
- requires Xray configuration validation to pass;
- stages deployment atomically and restores the previous configuration if restart or health checking fails.

Generated review files are written under the ignored `bash/output/` directory. Deployment targets `/usr/local/etc/xray/config.json` and requires appropriate `sudo` access.

## Repository layout

```text
app/        Flutter UI plus Android native pipeline
bash/       Linux generator and deployment workflow
go/         desktop/CLI Xray pipeline
scripts/    desktop bundling helpers
docs/       capability contract, specifications, and decisions
tasks/      implementation checklist
```

## Privacy and operational notes

- Proxy links and subscription URLs can contain credentials. Avoid posting logs or screenshots containing them.
- App preferences and sources the user explicitly saves are stored locally. Tested proxy results and one-off inline subscription URLs are not persisted.
- Network tests contact the selected test endpoint through each candidate proxy.
- Stopping Android work cancels queued coroutine work, but an already-running native JNI measurement cannot be force-killed safely inside the same app process.
- Public subscription sources are third-party data. Review their terms and security posture before use.

## License

[MIT](LICENSE)
