# proxysmith — xray config assembler with balancer and brutal connectivity test

A bash toolkit that automatically fetches, tests, deduplicates, and assembles a production-ready [Xray](https://github.com/XTLS/Xray-core) `config.json` from public proxy subscription feeds — daily, hands-free.

Built for Linux. Designed for operators who run Xray as a local or relay proxy and need a fresh, reliable outbound pool every day without manually testing thousands of configs.

---

## Scripts

| Script | Purpose |
|---|---|
| `proxysmith.sh` | Full 3-round pipeline: fetch → test → deduplicate → assemble → (optionally) deploy |
| `manualconfig.sh` | Skip the testing — parse a hand-picked list of URIs directly into a ready `config.json` |

---

## How it works

`proxysmith.sh` runs a 3-round brutal elimination pipeline:

```
~6000 raw configs (from subscription URL)
        │
        ▼  Round 1 — concurrent speedtest (configurable threads, default 50)
        │  deduplicate by proto:host:port
        │  filter by max latency (configurable, default 5000ms)
        ▼
   ~TOP_N×3 unique survivors  (default ~45)
        │
        ▼  Round 2 — concurrent speedtest again (same thread count)
        │  confirm Round 1 results, drop flukes
        ▼
    ~TOP_N confirmed configs  (default ~15)
        │
        ▼  Round 3 — single-threaded, one by one (threads=1)
        │  no parallel noise, most honest test
        ▼
      top 12 battle-hardened configs
        │
        ▼
  last_config.json   (Xray leastPing balancer — ready to deploy)
  last_configs.txt   (raw URIs — import into phone clients)
```

Only configs that survive all 3 rounds make it into the final `config.json`. The output uses Xray's `leastPing` balancer with observatory health checks so the best outbound is always selected at runtime automatically.

---

## Requirements

| Dependency | Purpose |
|---|---|
| `git` | will fetch the necessary packages during auto-install |
| `xray-knife` | Subscription fetch + proxy testing |
| `xray` | Config validation + runtime |
| `python3` | CSV parsing + JSON assembly |
| `jq` | JSON utility (used for validation) |
| `wget` | xray-knife download during auto-install |
| `unzip` | xray-knife extraction during auto-install |


> **You do not need to install these manually.** Both scripts include a built-in dependency checker that detects what is missing, shows you the install plan, and asks for confirmation before running. See [Dependency auto-installer](#dependency-auto-installer) below.

---

## Installation

```bash
git clone https://github.com/soroushyasini/proxysmith.git
cd proxysmith
chmod +x proxysmith.sh manualconfig.sh
```

---

## Running as root

> ⚠️ **`proxysmith.sh` and `manualconfig.sh --deploy` must be run as root** (or with `sudo`).
>
> Root is required for:
> - Installing dependencies (`apt-get`, moving binaries to `/usr/local/bin/`)
> - Deploying the config to `/usr/local/etc/xray/config.json`
> - Restarting the xray systemd service (`systemctl restart xray`)
>
> For the generate-only mode (no `--deploy`), root is still needed the first time if any dependencies are missing. Once all deps are installed you can run without root, but you will need to deploy manually.

```bash
# Recommended: run as root from the start
sudo bash proxysmith.sh
sudo bash proxysmith.sh --deploy
```

---

## Dependency auto-installer

On first run, the script checks for every required tool and shows a colour-coded status table:

```
  🔍  Checking dependencies
  ──────────────────────────────────────────────────
  [✗]  xray-knife         not in PATH — needs manual install
  [✗]  xray               not in PATH — needs manual install
  [✓]  python3            /usr/bin/python3
  [✗]  jq                 will install via apt
  [✓]  wget               /usr/bin/wget
  [✓]  unzip              /usr/bin/unzip
  ──────────────────────────────────────────────────

  Will install via apt:  jq

  Require a one-time download/install:
    xray-knife  →  downloaded from GitHub releases
    xray        →  installed via official XTLS installer script

  Install missing dependencies now? [Y/n]  (Enter = yes):
```

Answer `Y` (or just press Enter) and the script handles everything:
- `jq`, `python3`, `wget`, `unzip` → installed via `apt-get`
- `xray-knife` → downloaded from the latest GitHub release, moved to `/usr/local/bin/`
- `xray` → installed via the official `https://github.com/XTLS/Xray-install` script

A final re-check confirms all deps are present before the main run begins. On subsequent runs, if all deps are already installed, this step takes under a second and proceeds automatically.

---

## Usage — `proxysmith.sh`

### Interactive setup

Every run starts with an interactive prompt where you configure three parameters for that session:

```
  ⚙  Configure this run
  ──────────────────────────────────────────────────

  MAX_PING_MS
  Max latency threshold — configs slower than this are dropped in Round 1.
  Inside Iran, public configs typically range 1000–3000ms. Use 5000 for a wide net.
  Value [default: 5000, Enter to skip]:

  TOP_N
  Funnel size — Round 1 keeps TOP_N×3, Round 2 keeps TOP_N, Round 3 keeps 12.
  Higher = broader net + longer runtime. Lower = faster, may miss good configs.
  Value [default: 15, Enter to skip]:

  TEST_THREADS
  Parallel workers used in Round 1 & 2.
  50 works well on modern hardware. Drop to 10–20 on slow or low-RAM machines.
  Value [default: 50, Enter to skip]:
```

Just press Enter to accept all defaults and proceed.

### Generate only (no deployment)

```bash
sudo bash proxysmith.sh
```

The script will:
1. Run the dependency checker (installs anything missing)
2. Prompt for `MAX_PING_MS`, `TOP_N`, `TEST_THREADS` (Enter = defaults)
3. Fetch fresh configs from the subscription URL
4. Run 3 rounds of testing (~20–30 minutes for ~6000 configs at default settings)
5. Save results to `last_config.json` and `last_configs.txt` in the script directory
6. Print deploy instructions at the end

Deploy manually when ready:

```bash
sudo cp last_config.json /usr/local/etc/xray/config.json
sudo systemctl restart xray
```

### Generate + auto-deploy

```bash
sudo bash proxysmith.sh --deploy
```

Automatically backs up the existing config, deploys the new one, and restarts xray.

---

## Usage — `manualconfig.sh`

When you already have configs you trust and just want to package them — skip the whole testing pipeline and parse them directly into a `config.json`.

### Input file

Create `manualconfig.txt` in the same directory (one URI per line):

```
# lines starting with # are ignored
# blank lines are ignored

vless://your-uuid@your-server.com:443?type=tcp&security=reality&...#MyVless
ss://base64encodedstring@your-server.com:8388#MyShadowsocks
trojan://your-password@your-server.com:443?type=ws&path=/ws#MyTrojan
```

**Accepted protocols:** `vless://`, `vmess://`, `trojan://`, `ss://`, `tuic://`, `hysteria2://`, `hy2://`

### Run

```bash
# default: reads manualconfig.txt → writes manualconfig.json
sudo bash manualconfig.sh

# custom input file
sudo bash manualconfig.sh my_proxies.txt

# custom input + output
sudo bash manualconfig.sh proxies.txt output.json

# parse + deploy + restart xray
sudo bash manualconfig.sh --deploy
```

### Output

`manualconfig.json` — same structure as `proxysmith.sh` output: SOCKS5 inbound on `127.0.0.1:10808`, `leastPing` balancer, observatory, API, stats. Ready to deploy as-is.

---

## Fixed settings

These live at the top of `proxysmith.sh` and require editing the file to change:

```bash
SUB_URL="https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt"
SUB_REMARK="proxysmith-daily"
OUTPUT_CONFIG="/usr/local/etc/xray/config.json"   # where --deploy writes the config
SAVE_CONFIG="$SCRIPT_DIR/last_config.json"         # config backup (script directory)
SAVE_URIS="$SCRIPT_DIR/last_configs.txt"           # raw URIs output (script directory)
```

**Things you might want to change:**

- `SUB_URL` — any v2ray/xray subscription URL (raw text or base64-encoded list)
- `OUTPUT_CONFIG` — path where xray reads its config (verify with `systemctl cat xray`)

The three runtime parameters (`MAX_PING_MS`, `TOP_N`, `TEST_THREADS`) are set interactively at each run — no file editing needed.

---

## Output files

| File | Contents |
|---|---|
| `last_config.json` | Full Xray `config.json` ready to deploy (written to script directory) |
| `last_configs.txt` | One URI per line — import into v2rayNG, Hiddify, Shadowrocket, etc. |
| `manualconfig.json` | Output of `manualconfig.sh` — same format, different source |

---

## Inbound configuration

The generated config exposes a local SOCKS5 proxy:

| Setting | Value |
|---|---|
| Protocol | SOCKS5 |
| Listen | `127.0.0.1` |
| Port | `10808` |
| Auth | none |
| UDP | enabled |

Point your browser, system proxy, or other tools to `127.0.0.1:10808`.

For system-wide proxy on GNOME:

```bash
gsettings set org.gnome.system.proxy mode 'manual'
gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
gsettings set org.gnome.system.proxy.socks port 10808
```

---

## Using `last_configs.txt` on your phone

After each run, `last_configs.txt` contains the 12 best configs as raw URIs:

```
vless://...
ss://...
trojan://...
```

Import into any v2ray-compatible client:
- **v2rayNG** (Android) — tap `+` → Import from clipboard (paste all lines)
- **Hiddify** (Android/iOS) — Add profile → paste URI
- **Shadowrocket** (iOS) — scan QR or paste URI

---

## Automating with cron

To rebuild and deploy every day at 6am:

```bash
crontab -e
```

Add:

```
0 6 * * * /bin/bash /path/to/proxysmith.sh --deploy >> /var/log/proxysmith.log 2>&1
```

> Note: cron jobs run as the user whose crontab you edit. Use `root`'s crontab (`sudo crontab -e`) or prefix with `sudo` to ensure the deploy step has the required permissions.

### Or with a systemd timer

`/etc/systemd/system/proxysmith.timer`:

```ini
[Unit]
Description=Daily xray config rebuild

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

`/etc/systemd/system/proxysmith.service`:

```ini
[Unit]
Description=xray config builder

[Service]
Type=oneshot
ExecStart=/bin/bash /path/to/proxysmith.sh --deploy
StandardOutput=journal
StandardError=journal
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now proxysmith.timer
```

---

## Troubleshooting

**`0 configs passed the filter`**
Raise `MAX_PING_MS` at the interactive prompt — the network path from the test machine to proxy servers may be slow. Try `8000` or `10000`. Public configs tested from inside Iran often have 1000–3000ms latency.

**`Could not determine subscription ID`**
The subscription table format may have changed. Run `xray-knife subs show` and check the output manually — the script parses the first column as the ID.

**`xray config test failed`**
Check `journalctl -u xray -n 30`. Usually a permission issue on `/var/log/xray/error.log` — fix with:
```bash
sudo mkdir -p /var/log/xray && sudo chown nobody:nogroup /var/log/xray
```

**Round 3 takes too long**
Round 3 tests configs one-by-one with a full speedtest — for 15 configs expect 3–5 minutes. This is intentional: it is the most honest, interference-free measurement.

**Subscription fetch fails with DNS timeout**
Your network may block `raw.githubusercontent.com`. Route through a proxy first, or replace `SUB_URL` with an alternative mirror.

**`manualconfig.sh`: URI skipped with "unrecognised scheme"**
The URI prefix must be one of the accepted protocols listed above. Paste the full URI including the `://` part. Lines with unrecognised schemes are reported but do not abort the run — other URIs in the file are still processed.

**Dependency installer fails mid-way**
Re-run the script — the checker will detect what is still missing and only attempt to install those. Already-installed deps are skipped.

---

## Credits

- [xray-knife](https://github.com/lilendian0x00/xray-knife) — the engine that does all the heavy lifting
- [Xray-core](https://github.com/XTLS/Xray-core) — the proxy runtime
- [Epodonios/v2ray-configs](https://github.com/Epodonios/v2ray-configs) — default subscription source

---

## License

MIT
