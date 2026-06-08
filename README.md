# xray-config-builder

A bash script that automatically fetches, tests, deduplicates, and assembles a production-ready [Xray](https://github.com/XTLS/Xray-core) `config.json` from public proxy subscription feeds — daily, hands-free.

Built for Linux. Designed for operators who run Xray as a local or relay proxy and need a fresh, reliable outbound pool every day without manually testing thousands of configs.

---

## How it works

The script runs a 3-round brutal elimination pipeline:

```
~6000 raw configs (from subscription URL)
        │
        ▼  Round 1 — concurrent speedtest (threads=50)
        │  deduplicate by proto:host:port
        │  filter by max latency
        ▼
      ~90 unique survivors
        │
        ▼  Round 2 — concurrent speedtest again (threads=20)
        │  confirm Round 1 results, drop flukes
        ▼
      ~30 confirmed configs
        │
        ▼  Round 3 — single-threaded, one by one (threads=1)
        │  no parallel noise, most honest test
        ▼
      top 12 battle-hardened configs
        │
        ▼
  config.json  (Xray leastPing balancer)
  last_configs.txt  (raw URIs for phone/other clients)
```

Only configs that survive all 3 rounds make it into the final `config.json`. The output uses Xray's `leastPing` balancer with observatory health checks, so the best outbound is always selected at runtime automatically.

---

## Requirements

| Dependency | Purpose |
|---|---|
| `xray-knife` | Subscription fetch + proxy testing |
| `xray` | Config validation + runtime |
| `python3` | CSV parsing + JSON assembly |
| `jq` | JSON validation |

### Install xray-knife

```bash
wget https://github.com/lilendian0x00/xray-knife/releases/latest/download/Xray-knife-linux-64.zip
unzip Xray-knife-linux-64.zip
sudo mv xray-knife /usr/local/bin/
chmod +x /usr/local/bin/xray-knife
```

### Install xray

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

### Install other deps (Debian/Ubuntu)

```bash
sudo apt install python3 jq -y
```

---

## Installation

```bash
git clone https://github.com/YOUR_USERNAME/xray-config-builder.git
cd xray-config-builder
chmod +x build-xray-config.sh
```

---

## Configuration

Edit the tunables at the top of `build-xray-config.sh`:

```bash
# ── TUNABLES ──────────────────────────────────────────────────────────────────
SUB_URL="https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt"
SUB_REMARK="epodonios-daily"
MAX_PING_MS=5000        # discard configs slower than this in Round 1
TOP_N=15                # controls Round 1 → Round 2 funnel size (keeps TOP_N × 3)
TEST_THREADS=50         # parallel workers for Round 1 & 2
OUTPUT_CONFIG="/usr/local/etc/xray/config.json"   # xray config path
SAVE_CONFIG="/home/youruser/last_config.json"      # permanent config backup
SAVE_URIS="/home/youruser/last_configs.txt"        # raw URIs output file
# ─────────────────────────────────────────────────────────────────────────────
```

**Key settings to change for your setup:**

- `SUB_URL` — any v2ray/xray subscription URL (raw text or base64-encoded)
- `SAVE_CONFIG` / `SAVE_URIS` — change `youruser` to your Linux username
- `OUTPUT_CONFIG` — path where xray reads its config (check with `systemctl cat xray`)
- `MAX_PING_MS` — raise if you get 0 results (public configs from Iran often have 1000–3000ms latency on tested from inside Iran)
- `TEST_THREADS` — lower if your machine is low-powered or network is slow

---

## Usage

### Generate only (no deployment)

```bash
bash build-xray-config.sh
```

The script will:
1. Fetch fresh configs from the subscription URL
2. Run 3 rounds of testing (~25–30 minutes for 6000 configs)
3. Save results to `SAVE_CONFIG` and `SAVE_URIS`
4. Print deploy instructions at the end

Then deploy manually:

```bash
sudo cp ~/last_config.json /usr/local/etc/xray/config.json
sudo systemctl restart xray
```

### Generate + auto-deploy

```bash
sudo bash build-xray-config.sh --deploy
```

This automatically backs up the existing config, deploys the new one, and restarts xray.

---

## Output files

| File | Contents |
|---|---|
| `last_config.json` | Full Xray config.json ready to deploy |
| `last_configs.txt` | One URI per line — import into v2rayNG, Hiddify, etc. |

---

## Automating with cron

To rebuild and deploy every day at 6am:

```bash
crontab -e
```

Add:

```
0 6 * * * /bin/bash /path/to/build-xray-config.sh --deploy >> /var/log/xray-build.log 2>&1
```

Or with a systemd timer — create `/etc/systemd/system/xray-build.timer`:

```ini
[Unit]
Description=Daily xray config rebuild

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

And `/etc/systemd/system/xray-build.service`:

```ini
[Unit]
Description=xray config builder

[Service]
Type=oneshot
ExecStart=/bin/bash /path/to/build-xray-config.sh --deploy
StandardOutput=journal
StandardError=journal
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now xray-build.timer
```

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

## Using last_configs.txt on your phone

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

## Troubleshooting

**`0 configs passed the filter`**
Raise `MAX_PING_MS` — the testing machine's network path to proxy servers may be slow. Try `5000` (5 seconds).

**`Could not determine subscription ID`**
The subscription table format changed. Run `xray-knife subs show` and check the output — the script parses the first column as ID.

**`xray config test failed`**
Check `journalctl -u xray -n 30`. Usually a permission issue on `/var/log/xray/error.log` — fix with `sudo mkdir -p /var/log/xray && sudo chown xray:xray /var/log/xray`.

**Round 3 takes too long**
It tests configs one by one with a speedtest. For 30 configs expect ~5 minutes. This is intentional — it's the most honest test.

**Subscription fetch fails with DNS timeout**
Your network may block `raw.githubusercontent.com`. Try routing through a proxy first, or use an alternative mirror URL.

---

## Credits

- [xray-knife](https://github.com/lilendian0x00/xray-knife) — the engine that does all the heavy lifting
- [Xray-core](https://github.com/XTLS/Xray-core) — the proxy runtime
- [Epodonios/v2ray-configs](https://github.com/Epodonios/v2ray-configs) — default subscription source

---

## License

MIT
