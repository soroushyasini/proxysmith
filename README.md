# ProxySmith

A proxy subscription tester that fetches public v2ray/xray subscription lists,
tests each config against your real network, and returns the 10 fastest surviving
nodes ranked by latency.

Three implementations — same algorithm, different platforms:

| Component | Platform | Location |
|-----------|----------|----------|
| `bash/` | Linux/VPS (original) | Shell script, no dependencies |
| `go/` | Linux/Windows/Mac | Go CLI, xray-core library |
| `android/` | Android 5.0+ | Flutter UI + Kotlin + libv2ray.aar |

---

## How It Works

The core algorithm is a **3-round brutal elimination pipeline**:

```
Subscription URL
      │
      ▼
Fetch + base64 decode + filter valid URIs
      │
      ▼  uniform 1-in-N sampling
~1200 URIs
      │
      ├── Round 1  concurrency=20  keep top 60  maxPing=user_param
      │       ~9 min
      ├── Round 2  concurrency=5   keep top 30  no ping cutoff
      │       ~1.5 min
      └── Round 3  concurrency=1   keep top 10  no ping cutoff
              ~1.5 min
                │
                ▼
         Top 10 ranked by latency
```

Each URI is tested by spinning up a real xray-core instance, making an HTTP
request through it to `https://www.google.com/generate_204`, measuring the
round-trip time, and tearing the instance down. No shared state between tests.

**Validated output (June 2026, Finland VPS):**
```
6210 URIs fetched → 1242 sampled → Round 1 → 60 survivors
→ Round 2 → 30 survivors → Round 3 → 10 final results
Total runtime: ~12 min  |  Best latency: 102ms
```

---

## Component 1 — Bash (`bash/`)

Original implementation. Runs on any Linux box or VPS with `bash` and `curl`.
Uses the `xray` binary as a subprocess for latency testing.

### Requirements

- Linux (tested on Debian/Ubuntu)
- `xray` binary in PATH or set `XRAY_PATH` env var
- `curl`, `base64`, `jq`
- Internet access to the subscription URL and proxy endpoints

### Usage

```bash
cd bash/
chmod +x proxysmith.sh
./proxysmith.sh
```

Follow the interactive prompts:
- Subscription URL (press Enter for default)
- Sample rate (1=test all, 5=test 20%)
- Max ping cutoff in ms

Results written to `results.txt` (URIs only) and `results_with_ping.txt`
(latency + URI).

### Manual config test

```bash
./manualconfig.sh /path/to/config.json
```

Tests a single xray JSON config file directly.

---

## Component 2 — Go CLI (`go/`)

Clean library-style port of the bash pipeline. No shell dependencies — uses
xray-core as a Go library via `github.com/xtls/xray-core`.

### Requirements

- Go 1.23+ (`go version`)
- Network access to subscription URL and proxy endpoints
- If running from inside Iran: set `HTTPS_PROXY=socks5://HOST:PORT` or run on
  an external VPS

### Build

```bash
cd go/
go build -o proxysmith .
```

### Run

```bash
# Interactive mode
./proxysmith

# Quick smoke test on a local file
./proxysmith ~/last_configs.txt 4
```

### Go version pinning

The `go.mod` pins `github.com/xtls/xray-core v1.260327.0`. **Do not run
`go get github.com/xtls/xray-core@latest`** — later versions pull `quic-go`
and `gvisor` at incompatible versions. Always pin explicitly.

### File structure

```
go/
├── main.go       # Entry point: prompts config, runs pipeline, writes output
├── fetch.go      # HTTP fetch of sub URL, base64 decode, sampling
├── parser.go     # URI → xray outbound JSON (ss, vless, vmess, trojan)
├── pipeline.go   # runRound(): concurrent testing, sorting, filtering
├── measure.go    # measureDelay(): core latency primitive
├── register.go   # Blank-import side effects: registers all xray protocols
├── go.mod
└── go.sum
```

**Always run with `go run .` (not `go run main.go`)** — all files including
`register.go` must be compiled together or protocol registration silently fails.

---

## Component 3 — Android App (`android/`)

Flutter UI over a Kotlin backend. The Kotlin layer runs the same 3-round
pipeline using `libv2ray.aar` (AndroidLibXrayLite) as the xray-core engine.
Flutter communicates with Kotlin via MethodChannel + EventChannel.

### Architecture

```
Flutter UI (Dart)
      │  MethodChannel "ir.proxysmith/pipeline"
      │  EventChannel  "ir.proxysmith/progress"
      ▼
MainActivity.kt  (bridge)
      │
      ├── SubscriptionFetcher.kt  — HTTP fetch, base64 decode, sampling
      ├── UriParser.kt            — URI → xray outbound JSON
      ├── Pipeline.kt             — 3-round coroutine pipeline
      └── libv2ray.aar            — measureOutboundDelay() JNI
```

### Requirements

- Flutter 3.x (`flutter --version`)
- Android Studio with an emulator or physical device (Android 5.0+, API 21+)
- `libv2ray.aar` — see build instructions below

### Getting the AAR

The AAR is stored in this repo via **git-lfs**. Pull it with:

```bash
git lfs pull
```

The file will appear at `android/app/libs/libv2ray.aar` (~40MB).

If git-lfs is not available, build the AAR from source — see
**Building libv2ray.aar** below.

### Run the app

```bash
cd android/
flutter pub get
flutter run
```

Flutter will build and deploy to the connected emulator or device.

### Gradle configuration

```
AGP:        8.7.3
Gradle:     9.4.1
Kotlin:     2.0.21
compileSdk: 35 (via flutter.compileSdkVersion)
minSdk:     21
namespace:  ir.proxysmith.proxysmith_flutter
```

Key dependencies in `android/app/build.gradle.kts`:
```kotlin
implementation(files("libs/libv2ray.aar"))
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
```

`android/android/gradle.properties` must contain:
```properties
android.useAndroidX=true
```

---

## Building libv2ray.aar from Source

If you can't use git-lfs or want to rebuild the AAR yourself:

### Build environment

- Debian/Ubuntu Linux (VPS or WSL)
- Java 17: `sudo apt install openjdk-17-jdk-headless`

### Install Go

```bash
wget https://go.dev/dl/go1.26.4.linux-amd64.tar.gz
tar -C $HOME -xzf go1.26.4.linux-amd64.tar.gz
export PATH=$PATH:$HOME/go/bin
```

### Install gomobile (pinned version)

```bash
HTTPS_PROXY=socks5://YOUR_PROXY \
  go install golang.org/x/mobile/cmd/gomobile@v0.0.0-20260529142300-ecb4cd65260a

HTTPS_PROXY=socks5://YOUR_PROXY \
  go install golang.org/x/mobile/cmd/gobind@v0.0.0-20260529142300-ecb4cd65260a
```

**Do not use `@latest`** — the latest gomobile uses Go 1.24+ tool directive
semantics that conflict with AndroidLibXrayLite's go.mod.

### Install Android SDK + NDK

```bash
sudo apt install unzip wget
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip commandlinetools-linux-11076708_latest.zip -d android-sdk
mkdir -p android-sdk/cmdline-tools/latest
mv android-sdk/cmdline-tools/* android-sdk/cmdline-tools/latest/

export ANDROID_HOME=$HOME/android-sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin

# NDK — note: sdkmanager is Java, use --proxy flags not env vars
sdkmanager "ndk;27.2.12479018" "platforms;android-21" \
  --proxy=socks --proxy_host=YOUR_PROXY_HOST --proxy_port=YOUR_PROXY_PORT
```

### Clone and build

```bash
mkdir -p ~/arr && cd ~/arr
git clone https://github.com/2dust/AndroidLibXrayLite

cd AndroidLibXrayLite
HTTPS_PROXY=socks5://YOUR_PROXY go mod tidy -v

export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.2.12479018
export HTTPS_PROXY=socks5://YOUR_PROXY
export GOPROXY=direct
export GONOSUMDB=*

# GOTOOLCHAIN=go1.23.10 is required — anet is incompatible with Go 1.24+
GOTOOLCHAIN=go1.23.10 gomobile bind -v -androidapi 21 -ldflags='-s -w' ./
```

Build time: 5–15 minutes. Output: `libv2ray.aar` (~40MB).

Copy to the Flutter project:
```bash
cp libv2ray.aar /path/to/proxysmith/android/app/libs/
```

### Why Go 1.23?

`AndroidLibXrayLite` depends on `github.com/wlynxg/anet` which references
`net.zoneCache`, a private symbol removed in Go 1.24. The system Go can be
1.26+ — `GOTOOLCHAIN=go1.23.10` tells Go to download and use 1.23.10 just
for this build.

---

## Supported Proxy Protocols

| Protocol | Transports | Notes |
|----------|-----------|-------|
| VLESS | TCP, WS, gRPC, H2 | TLS, Reality, none |
| VMess | TCP, WS, gRPC | TLS, none |
| Trojan | TCP, WS, gRPC | TLS always |
| Shadowsocks | TCP | base64 and plain userinfo |
| tuic:// | — | fetched/sampled but skipped in testing |
| hysteria2:// | — | fetched/sampled but skipped in testing |

---

## Default Subscription Source

```
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt
```

Any standard v2ray subscription URL works (base64-encoded or plain text,
one URI per line).

---

## Network Notes

- The device/VPS running the test must have open access to the proxy endpoints
- From inside Iran: run on an external VPS, or ensure an upstream proxy is
  configured (`HTTPS_PROXY` for Go, system proxy for Android)
- The Android app runs the full pipeline on-device — a foreground service is
  recommended for the ~12 minute run to prevent Android from killing it

---

## Validated Results (June 2026)

| Platform | Best latency | Total runtime | URIs tested |
|----------|-------------|---------------|-------------|
| Finland VPS (Go) | 104ms | 9m 8s | 1242 of 6210 |
| Android x86_64 emulator | 102ms | ~12 min | 1454 of 7270 |

---

## License

MIT
