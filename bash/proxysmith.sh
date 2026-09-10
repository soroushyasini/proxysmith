#!/usr/bin/env bash
# ProxySmith server pipeline. Dependencies are never installed automatically.
set -Eeuo pipefail
umask 077

SUB_URL="https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt"
SUB_REMARK="proxysmith-daily"
TEST_URL="https://cp.cloudflare.com/generate_204"
OUTPUT_CONFIG="/usr/local/etc/xray/config.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proxysmith.XXXXXXXX")"
SUB_ID=""
DEPLOY=false

case "${1:-}" in
  "") ;;
  --deploy) DEPLOY=true ;;
  *) echo "usage: $0 [--deploy]" >&2; exit 2 ;;
esac

log() { printf '[*] %s\n' "$*"; }
ok() { printf '[+] %s\n' "$*"; }
die() { printf '[!] %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "$SUB_ID" ]] && command -v xray-knife >/dev/null 2>&1; then
    printf 'y\n' | xray-knife subs rm "$SUB_ID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" && "$WORK_DIR" == "${TMPDIR:-/tmp}/proxysmith."* ]]; then
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT INT TERM

check_dependencies() {
  local missing=()
  local command_name
  for command_name in xray-knife xray python3; do
    command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
  done
  if ((${#missing[@]})); then
    printf 'Missing required commands: %s\n' "${missing[*]}" >&2
    printf 'Install them from your operating-system or upstream package source, verify their provenance, and retry.\n' >&2
    exit 1
  fi
}

read_integer() {
  local prompt="$1" default_value="$2" minimum="$3" maximum="$4" value
  read -r -p "$prompt [$default_value]: " value
  value="${value:-$default_value}"
  [[ "$value" =~ ^[0-9]+$ ]] || die "Expected a whole number for $prompt"
  ((value >= minimum && value <= maximum)) || die "$prompt must be between $minimum and $maximum"
  printf '%s' "$value"
}

filter_csv() {
  local csv_path="$1" max_ping="$2" keep_count="$3" output_path="$4"
  python3 - "$csv_path" "$max_ping" "$keep_count" "$output_path" <<'PY'
import csv
import sys
from urllib.parse import urlsplit

csv_path, max_ping, keep_count, output_path = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
supported = {"vless", "vmess", "trojan", "ss", "hysteria2", "hy2"}
csv.field_size_limit(10 * 1024 * 1024)
rows, seen = [], set()
with open(csv_path, encoding="latin-1", errors="replace") as source:
    reader = csv.DictReader(line.replace("\x00", "") for line in source)
    for row in reader:
        try:
            if row.get("status", "").strip() != "passed":
                continue
            latency = int(row["delay"])
            uri = row["link"].strip()
            clean = uri.split("#", 1)[0]
            scheme = urlsplit(clean).scheme.lower()
            if latency <= 0 or (max_ping and latency > max_ping) or scheme not in supported or clean in seen:
                continue
            seen.add(clean)
            rows.append((latency, uri))
        except (KeyError, TypeError, ValueError):
            continue
rows.sort(key=lambda item: item[0])
selected = rows[:keep_count]
with open(output_path, "w", encoding="utf-8") as destination:
    for latency, uri in selected:
        destination.write(f"{latency}\t{uri}\n")
print(f"Selected {len(selected)} of {len(rows)} passing unique configurations")
PY
  [[ -s "$output_path" ]] || die "No configurations survived this round"
}

run_file_round() {
  local input_path="$1" output_csv="$2" threads="$3"
  xray-knife http -f "$input_path" --speedtest --sort --type csv -o "$output_csv" \
    --thread "$threads" --url "$TEST_URL"
  [[ -s "$output_csv" ]] || die "The test tool did not produce results"
}

check_dependencies
MAX_PING_MS="$(read_integer 'Maximum Round 1 latency in ms' 5000 0 60000)"
TEST_THREADS="$(read_integer 'Concurrent test workers' 20 1 60)"

log "Refreshing the dedicated ProxySmith subscription"
mapfile -t existing_ids < <(xray-knife subs show 2>/dev/null | awk -v remark="$SUB_REMARK" '$0 ~ remark && $1 ~ /^[0-9]+$/ {print $1}')
for existing_id in "${existing_ids[@]}"; do
  printf 'y\n' | xray-knife subs rm "$existing_id" >/dev/null
done
xray-knife subs add --url "$SUB_URL" --remark "$SUB_REMARK"
SUB_ID="$(xray-knife subs show 2>/dev/null | awk -v remark="$SUB_REMARK" '$0 ~ remark && $1 ~ /^[0-9]+$/ {print $1; exit}')"
[[ "$SUB_ID" =~ ^[0-9]+$ ]] || die "Could not identify the ProxySmith subscription"
xray-knife subs fetch --id "$SUB_ID"

log "Round 1: testing the subscription"
ROUND1_CSV="$WORK_DIR/round1.csv"
xray-knife http --from-db --sub-id "$SUB_ID" --speedtest --sort --type csv -o "$ROUND1_CSV" \
  --thread "$TEST_THREADS" --url "$TEST_URL"
[[ -s "$ROUND1_CSV" ]] || die "Round 1 did not produce results"
filter_csv "$ROUND1_CSV" "$MAX_PING_MS" 60 "$WORK_DIR/round1.txt"

log "Round 2: confirming the 60 best candidates"
cut -f2- "$WORK_DIR/round1.txt" > "$WORK_DIR/round1_uris.txt"
run_file_round "$WORK_DIR/round1_uris.txt" "$WORK_DIR/round2.csv" 5
filter_csv "$WORK_DIR/round2.csv" 0 30 "$WORK_DIR/round2.txt"

log "Round 3: final single-worker ranking"
cut -f2- "$WORK_DIR/round2.txt" > "$WORK_DIR/round2_uris.txt"
run_file_round "$WORK_DIR/round2_uris.txt" "$WORK_DIR/round3.csv" 1
filter_csv "$WORK_DIR/round3.csv" 0 10 "$WORK_DIR/winners.txt"

OUTBOUNDS_JSON="$WORK_DIR/outbounds.json"
python3 - "$WORK_DIR/winners.txt" "$OUTBOUNDS_JSON" <<'PY'
import json
import subprocess
import sys

winners_path, output_path = sys.argv[1:]
outbounds, tags, counters = [], [], {}
for line in open(winners_path, encoding="utf-8"):
    _, uri = line.rstrip("\n").split("\t", 1)
    protocol = uri.split("://", 1)[0].lower()
    completed = subprocess.run(
        ["xray-knife", "parse", "-c", uri, "--json"],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        continue
    try:
        parsed = json.loads(completed.stdout)
    except json.JSONDecodeError:
        continue
    candidates = parsed.get("outbounds", []) if "outbounds" in parsed else [parsed]
    outbound = next((item for item in candidates if item.get("protocol") not in {"freedom", "blackhole"}), None)
    if not outbound:
        continue
    counters[protocol] = counters.get(protocol, 0) + 1
    tag = f"{protocol}_{counters[protocol]:02d}"
    outbound["tag"] = tag
    outbounds.append(outbound)
    tags.append(tag)
if not outbounds:
    raise SystemExit("No winning URI could be converted to an Xray outbound")
with open(output_path, "w", encoding="utf-8") as destination:
    json.dump({"outbounds": outbounds, "tags": tags}, destination)
PY

FINAL_CONFIG="$WORK_DIR/config.json"
python3 - "$OUTBOUNDS_JSON" "$FINAL_CONFIG" "$TEST_URL" <<'PY'
import json
import sys

source_path, destination_path, test_url = sys.argv[1:]
data = json.load(open(source_path, encoding="utf-8"))
outbounds, tags = data["outbounds"], data["tags"]
outbounds += [
    {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}},
    {"tag": "blocked", "protocol": "blackhole", "settings": {}},
]
config = {
    "log": {"loglevel": "warning", "error": "/var/log/xray/error.log"},
    "inbounds": [{"listen": "127.0.0.1", "port": 10808, "protocol": "socks", "settings": {"auth": "noauth", "udp": True}}],
    "outbounds": outbounds,
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"},
            {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "blocked"},
            {"type": "field", "protocol": ["bittorrent"], "outboundTag": "blocked"},
            {"type": "field", "network": "tcp,udp", "balancerTag": "fast-tier"},
        ],
        "balancers": [{"tag": "fast-tier", "selector": tags, "fallbackTag": tags[0], "strategy": {"type": "leastPing"}}],
    },
    "observatory": {"subjectSelector": tags, "probeURL": test_url, "probeInterval": "5s", "enableConcurrency": False},
}
with open(destination_path, "w", encoding="utf-8") as destination:
    json.dump(config, destination, indent=2)
PY

log "Validating the generated configuration with Xray"
if ! xray run -test -config "$FINAL_CONFIG"; then
  die "Xray rejected the generated configuration; nothing was deployed"
fi
mkdir -p "$OUTPUT_DIR"
install -m 0600 "$FINAL_CONFIG" "$OUTPUT_DIR/last_config.json"
cut -f2- "$WORK_DIR/winners.txt" > "$OUTPUT_DIR/last_configs.txt"
ok "Validated output saved under $OUTPUT_DIR"

if [[ "$DEPLOY" == true ]]; then
  BACKUP="${OUTPUT_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
  had_previous=false
  if sudo test -f "$OUTPUT_CONFIG"; then
    sudo cp -- "$OUTPUT_CONFIG" "$BACKUP"
    had_previous=true
  fi
  sudo install -m 0644 "$FINAL_CONFIG" "${OUTPUT_CONFIG}.new"
  sudo mv -- "${OUTPUT_CONFIG}.new" "$OUTPUT_CONFIG"
  if ! sudo systemctl restart xray || ! sudo systemctl is-active --quiet xray; then
    if [[ "$had_previous" == true ]]; then
      sudo cp -- "$BACKUP" "$OUTPUT_CONFIG"
      sudo systemctl restart xray || true
      die "Deployment failed; the previous configuration was restored"
    fi
    sudo rm -f -- "$OUTPUT_CONFIG"
    die "Deployment failed and there was no previous configuration to restore"
  fi
  ok "Deployed successfully; backup: $BACKUP"
else
  printf 'Re-run with --deploy after reviewing %s\n' "$OUTPUT_DIR/last_config.json"
fi
