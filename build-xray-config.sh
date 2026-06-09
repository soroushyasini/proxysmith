#!/usr/bin/env bash
# =============================================================================
# build-xray-config.sh  —  RomanLegioner daily config builder
# Requires: xray-knife (in PATH), python3, jq
# Usage:
#   bash build-xray-config.sh            # generate only
#   bash build-xray-config.sh --deploy   # generate + deploy + restart xray
# =============================================================================

set -euo pipefail

# ── FIXED SETTINGS ───────────────────────────────────────────────────────────
SUB_URL="https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt"
SUB_REMARK="proxysmith-daily"
OUTPUT_CONFIG="/usr/local/etc/xray/config.json"
WORK_DIR="/tmp/roman-build-$$"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAVE_CONFIG="$SCRIPT_DIR/last_config.json"
SAVE_URIS="$SCRIPT_DIR/last_configs.txt"
# ─────────────────────────────────────────────────────────────────────────────

# ── INTERACTIVE SETUP ──────────────────────────────────────────────────────────────
DIM='\033[2m'; WHITE='\033[1;97m'; GREY='\033[0;90m'
interactive_setup() {
    echo -e "\n${WHITE}  ⚙  Configure this run${NC}"
    echo -e "${GREY}  ──────────────────────────────────────────────────${NC}\n"

    echo -e "  ${BOLD}MAX_PING_MS${NC}"
    echo -e "  ${DIM}Max latency threshold — configs slower than this are dropped in Round 1.${NC}"
    echo -e "  ${DIM}Inside Iran, public configs typically range 1000–3000ms. Use 5000 for a wide net.${NC}"
    read -rp "  Value [default: 5000, Enter to skip]: " input_ping
    MAX_PING_MS="${input_ping:-5000}"

    echo ""
    echo -e "  ${BOLD}TOP_N${NC}"
    echo -e "  ${DIM}Funnel size — Round 1 keeps TOP_N×3, Round 2 keeps TOP_N, Round 3 keeps 12.${NC}"
    echo -e "  ${DIM}Higher = broader net + longer runtime. Lower = faster, may miss good configs.${NC}"
    read -rp "  Value [default: 15, Enter to skip]: " input_topn
    TOP_N="${input_topn:-15}"

    echo ""
    echo -e "  ${BOLD}TEST_THREADS${NC}"
    echo -e "  ${DIM}Parallel workers used in Round 1 & 2.${NC}"
    echo -e "  ${DIM}50 works well on modern hardware. Drop to 10–20 on slow or low-RAM machines.${NC}"
    read -rp "  Value [default: 50, Enter to skip]: " input_threads
    TEST_THREADS="${input_threads:-50}"

    echo ""
    echo -e "${GREY}  ──────────────────────────────────────────────────${NC}"
    printf "  ${DIM}%-14s${NC}  ${GREEN}%s ms${NC}\n" "MAX_PING_MS" "${MAX_PING_MS}"
    printf "  ${DIM}%-14s${NC}  ${GREEN}%s${NC}  ${DIM}(R1: %s → R2: %s → R3: 12)${NC}\n" "TOP_N" "${TOP_N}" "$((TOP_N * 3))" "${TOP_N}"
    printf "  ${DIM}%-14s${NC}  ${GREEN}%s${NC}\n" "TEST_THREADS" "${TEST_THREADS}"
    echo -e "${GREY}  ──────────────────────────────────────────────────${NC}\n"
    read -rp "  Proceed? [Y/n]  (Enter to continue): " confirm
    [[ "${confirm,,}" == "n" ]] && echo -e "\n  Aborted." && exit 0
    echo ""
}

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

# ── BANNER ────────────────────────────────────────────────────────────────────
print_banner() {
    echo -e "\033[0;31m"
    cat << 'BANNER'
  ██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗███████╗███╗   ███╗██╗████████╗██╗  ██╗
  ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝██╔════╝████╗ ████║██║╚══██╔══╝██║  ██║
  ██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝ ███████╗██╔████╔██║██║   ██║   ███████║
  ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝  ╚════██║██║╚██╔╝██║██║   ██║   ██╔══██║
  ██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║   ███████║██║ ╚═╝ ██║██║   ██║   ██║  ██║
  ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚═╝   ╚═╝   ╚═╝  ╚═╝
BANNER

    echo -e "\033[1;37m    The 3-Round Brutal Xray Config Builder With auto Balancer and xray Deployment\033[0m"
    echo -e "\033[0;90m            ─────────────────────────────────────────────────────────────\033[0m"
    echo -e "\033[0;90m            Author  :  Soroush Yasini\033[0m"
    echo -e "\033[0;90m            Repo    :  https://github.com/soroushyasini/proxysmith\033[0m"
    echo -e "\033[0;90m            Email   :  soroush.yasini5@gmail.com\033[0m"
    echo -e "\033[0;90m            LinkedIn:  linkedin.com/in/soroush-yasini\033[0m"
    echo -e "\033[0;90m            ─────────────────────────────────────────────────────────────\033[0m"
    echo ""
}
print_banner
interactive_setup
# ─────────────────────────────────────────────────────────────────────────────
for cmd in xray-knife python3 jq; do
    command -v "$cmd" &>/dev/null || die "Missing dependency: $cmd
    Follow the README.md for Dependency installation guide"
done

mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

CSV="$WORK_DIR/results.csv"
OUTBOUNDS_JSON="$WORK_DIR/outbounds.json"
FINAL_CONFIG="$WORK_DIR/config.json"

# =============================================================================
# STEP 1 — always start clean: remove existing sub, re-add, fetch fresh
# =============================================================================
log "Cleaning up existing subscriptions..."

xray-knife subs show 2>/dev/null \
    | awk 'NR>2 && $1 ~ /^[0-9]+$/ {print $1}' \
    | while read -r id; do
        echo y | xray-knife subs rm "$id" 2>/dev/null && log "Removed sub ID=$id"
    done

log "Adding subscription..."
xray-knife subs add --url "$SUB_URL" --remark "$SUB_REMARK"

SUB_ID=$(xray-knife subs show 2>/dev/null \
    | awk -v r="$SUB_REMARK" '$0 ~ r {print $1; exit}')

[ -z "$SUB_ID" ] && die "Could not determine subscription ID"
ok "Subscription added (ID=$SUB_ID)"

log "Fetching configs for sub ID=$SUB_ID..."
xray-knife subs fetch --id "$SUB_ID"
ok "Subscription fetched"

# =============================================================================
# STEP 2 — test all configs, output sorted CSV
# =============================================================================
log "Testing configs (threads=$TEST_THREADS, this takes a few minutes)..."

xray-knife http \
    --from-db --sub-id "$SUB_ID" \
    --speedtest \
    --sort \
    --type csv \
    -o "$CSV" \
    --thread "$TEST_THREADS" \
    --url "https://www.google.com/generate_204"

[ -f "$CSV" ] || die "xray-knife did not produce a CSV file"
TOTAL=$(( $(wc -l < "$CSV") - 1 ))   # minus header
ok "Tested $TOTAL configs, results in CSV"

# =============================================================================
# STEP 3 — parse CSV, deduplicate by host:port, filter by latency, pick top N
# =============================================================================
log "Filtering + deduplicating (latency < ${MAX_PING_MS}ms)..."

python3 << PYEOF
import csv, sys, urllib.parse
csv.field_size_limit(10 * 1024 * 1024)

csv_path = "$CSV"
max_ping = $MAX_PING_MS
top_n    = $TOP_N * 3   # keep 3x for round-2 testing
out_path = "$WORK_DIR/round1_winners.txt"

def uri_key(uri):
    """Deduplicate key: proto:host:port only — different UUIDs on same server = same key."""
    try:
        base = uri.split('#')[0]
        parsed = urllib.parse.urlparse(base)
        return f"{parsed.scheme}:{parsed.hostname}:{parsed.port}"
    except Exception:
        return uri.split('#')[0]

with open(csv_path, newline="", encoding="latin-1") as f:
    reader = csv.DictReader(f)
    rows = []
    seen_keys = set()
    for row in reader:
        try:
            if row.get('status','').strip() != 'passed':
                continue
            lat = int(row['delay'])
            if lat <= 0 or lat > max_ping:
                continue
            cfg = row['link'].strip()
            if not cfg:
                continue
            key = uri_key(cfg)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            rows.append((lat, cfg))
        except (ValueError, KeyError):
            continue

rows.sort(key=lambda x: x[0])
selected = rows[:top_n]

with open(out_path, 'w') as f:
    for lat, cfg in selected:
        f.write(f"{lat}\t{cfg}\n")

print(f"Round 1: {len(selected)} unique configs (from {len(rows)} passing filter, duplicates removed)")
for lat, cfg in selected[:10]:
    proto = cfg.split('://')[0]
    print(f"  {lat:>5}ms  {proto:<10}  {cfg[:65]}")
if len(selected) > 10:
    print(f"  ... and {len(selected)-10} more")
PYEOF

[ -f "$WORK_DIR/round1_winners.txt" ] || die "No configs passed the filter"
R1_COUNT=$(wc -l < "$WORK_DIR/round1_winners.txt")
ok "Round 1: $R1_COUNT unique configs selected"

# =============================================================================
# STEP 3b — second test round on survivors only
# =============================================================================
log "Round 2: re-testing $R1_COUNT survivors for confirmation..."

# Write URIs to a temp file for xray-knife to consume
awk -F'\t' '{print $2}' "$WORK_DIR/round1_winners.txt" > "$WORK_DIR/round1_uris.txt"

CSV2="$WORK_DIR/results_round2.csv"
xray-knife http     -f "$WORK_DIR/round1_uris.txt"     --speedtest     --sort     --type csv     -o "$CSV2"     --thread "$TEST_THREADS"     --url "https://www.google.com/generate_204"

[ -f "$CSV2" ] || die "Round 2 produced no CSV"

python3 << PYEOF
import csv, urllib.parse
csv.field_size_limit(10 * 1024 * 1024)

csv_path = "$CSV2"
top_n    = $TOP_N
out_path = "$WORK_DIR/winners.txt"

def uri_key(uri):
    try:
        base = uri.split('#')[0]
        parsed = urllib.parse.urlparse(base)
        return f"{parsed.scheme}:{parsed.hostname}:{parsed.port}"
    except Exception:
        return uri.split('#')[0]

with open(csv_path, newline="", encoding="latin-1") as f:
    reader = csv.DictReader(f)
    rows = []
    seen_keys = set()
    for row in reader:
        try:
            if row.get('status','').strip() != 'passed':
                continue
            lat = int(row['delay'])
            if lat <= 0:
                continue
            cfg = row['link'].strip()
            if not cfg:
                continue
            key = uri_key(cfg)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            rows.append((lat, cfg))
        except (ValueError, KeyError):
            continue

rows.sort(key=lambda x: x[0])
selected = rows[:top_n]

with open(out_path, 'w') as f:
    for lat, cfg in selected:
        f.write(f"{lat}\t{cfg}\n")

print(f"Round 2: {len(selected)} confirmed configs (from {len(rows)} re-tested)")
for lat, cfg in selected:
    proto = cfg.split('://')[0]
    print(f"  {lat:>5}ms  {proto:<10}  {cfg[:65]}")
PYEOF

[ -f "$WORK_DIR/winners.txt" ] || die "No configs survived round 2"
R2_COUNT=$(wc -l < "$WORK_DIR/winners.txt")
ok "Round 2 done: $R2_COUNT configs confirmed"

# =============================================================================
# STEP 3c — round 3: single-threaded brutal final test, pick best 12
# =============================================================================
log "Round 3: single-threaded final test on $R2_COUNT survivors..."

awk -F'\t' '{print $2}' "$WORK_DIR/winners.txt" > "$WORK_DIR/round2_uris.txt"

CSV3="$WORK_DIR/results_round3.csv"
xray-knife http \
    -f "$WORK_DIR/round2_uris.txt" \
    --speedtest \
    --sort \
    --type csv \
    -o "$CSV3" \
    --thread 1 \
    --url "https://www.google.com/generate_204"

[ -f "$CSV3" ] || die "Round 3 produced no CSV"

python3 << PYEOF
import csv, urllib.parse
csv.field_size_limit(10 * 1024 * 1024)

csv_path = "$CSV3"
top_n    = 12
out_path = "$WORK_DIR/final_winners.txt"

def uri_key(uri):
    try:
        base = uri.split('#')[0]
        parsed = urllib.parse.urlparse(base)
        return f"{parsed.scheme}:{parsed.hostname}:{parsed.port}"
    except Exception:
        return uri.split('#')[0]

with open(csv_path, newline="", encoding="latin-1") as f:
    reader = csv.DictReader(f)
    rows = []
    seen_keys = set()
    for row in reader:
        try:
            if row.get('status','').strip() != 'passed':
                continue
            lat = int(row['delay'])
            if lat <= 0:
                continue
            cfg = row['link'].strip()
            if not cfg:
                continue
            key = uri_key(cfg)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            rows.append((lat, cfg))
        except (ValueError, KeyError):
            continue

rows.sort(key=lambda x: x[0])
selected = rows[:top_n]

with open(out_path, 'w') as f:
    for lat, cfg in selected:
        f.write(f"{lat}\t{cfg}\n")

print(f"Round 3: {len(selected)} final configs (from {len(rows)} passing, {$R2_COUNT - len(rows)} dropped)")
for lat, cfg in selected:
    proto = cfg.split('://')[0]
    print(f"  {lat:>5}ms  {proto:<10}  {cfg[:65]}")
PYEOF

[ -f "$WORK_DIR/final_winners.txt" ] || die "No configs survived round 3"
FINAL_COUNT=$(wc -l < "$WORK_DIR/final_winners.txt")
ok "Final selection: $FINAL_COUNT configs survived all 3 rounds"

# Overwrite winners.txt with final selection so STEP 4 uses it
cp "$WORK_DIR/final_winners.txt" "$WORK_DIR/winners.txt"
awk -F'\t' '{print $2}' "$WORK_DIR/winners.txt" > "$SAVE_URIS"
ok "URIs saved to $SAVE_URIS"

# =============================================================================
# STEP 4 — convert each winning URI to xray outbound JSON via xray-knife parse
# =============================================================================
log "Parsing winning configs into Xray outbound JSON..."

python3 << PYEOF
import subprocess, json, sys, re

winners_path = "$WORK_DIR/winners.txt"
outbounds_path = "$OUTBOUNDS_JSON"

lines = open(winners_path).read().splitlines()
outbounds = []
tags = []
proto_counters = {}
errors = []

for line in lines:
    if '\t' not in line:
        continue
    ms, uri = line.split('\t', 1)
    uri = uri.strip()
    proto = uri.split('://')[0]

    try:
        result = subprocess.run(
            ['xray-knife', 'parse', '-c', uri, '--json'],
            capture_output=True, text=True, timeout=10
        )
        raw = result.stdout.strip()
        if not raw:
            errors.append(f"empty output for {uri[:60]}")
            continue

        # xray-knife parse --json may wrap outbound in a full config or return
        # just the outbound object — handle both
        obj = json.loads(raw)

        # If it's a full config, extract the first non-freedom/blackhole outbound
        if 'outbounds' in obj:
            ob = next(
                (o for o in obj['outbounds']
                 if o.get('protocol') not in ('freedom', 'blackhole')),
                None
            )
        elif 'protocol' in obj:
            ob = obj
        else:
            errors.append(f"unexpected JSON shape for {uri[:60]}: {list(obj.keys())}")
            continue

        if not ob:
            errors.append(f"no usable outbound in {uri[:60]}")
            continue

        # Assign clean tag
        proto_counters[proto] = proto_counters.get(proto, 0) + 1
        tag = f"{proto}_{proto_counters[proto]:02d}"
        ob['tag'] = tag

        outbounds.append(ob)
        tags.append(tag)
        print(f"  ✓  {tag:<14}  {uri[:65]}")

    except subprocess.TimeoutExpired:
        errors.append(f"timeout: {uri[:60]}")
    except json.JSONDecodeError as e:
        errors.append(f"json error ({e}) for {uri[:60]}")
    except Exception as e:
        errors.append(f"{e}: {uri[:60]}")

if errors:
    print(f"\n  Skipped {len(errors)} configs:")
    for e in errors:
        print(f"    - {e}")

with open(outbounds_path, 'w') as f:
    json.dump({'outbounds': outbounds, 'tags': tags}, f)

print(f"\nParsed {len(outbounds)} outbound objects")
if not outbounds:
    sys.exit(1)
PYEOF

ok "Outbound JSON ready"

# =============================================================================
# STEP 5 — assemble final config.json
# =============================================================================
log "Assembling config.json..."

python3 << PYEOF
import json

data = json.load(open("$OUTBOUNDS_JSON"))
outbounds = data['outbounds']
tags = data['tags']

# Append fixed outbounds
outbounds.append({"tag": "direct",  "protocol": "freedom",   "settings": {"domainStrategy": "UseIPv4"}})
outbounds.append({"tag": "blocked", "protocol": "blackhole", "settings": {}})

config = {
    "inbounds": [
        {
            "listen": "127.0.0.1",
            "port": 10808,
            "protocol": "socks",
            "settings": {"auth": "noauth", "udp": True}
        },
        {
            "listen": "127.0.0.1",
            "port": 62789,
            "protocol": "tunnel",
            "settings": {"address": "127.0.0.1"},
            "tag": "api"
        }
    ],
    "outbounds": outbounds,
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {"type": "field", "inboundTag": ["api"],                     "outboundTag": "api"},
            {"type": "field", "ip":         ["geoip:private"],           "outboundTag": "blocked"},
            {"type": "field", "domain":     ["geosite:category-ads-all"],"outboundTag": "blocked"},
            {"type": "field", "protocol":   ["bittorrent"],              "outboundTag": "blocked"},
            {"type": "field", "network":    "tcp,udp",                   "balancerTag":  "fast-tier"}
        ],
        "balancers": [{
            "tag": "fast-tier",
            "selector": tags,
            "fallbackTag": tags[0],
            "strategy": {"type": "leastPing"}
        }]
    },
    "log": {
        "loglevel": "warning",
        "error": "/var/log/xray/error.log"
    },
    "policy": {
        "system": {
            "statsInboundDownlink":  True, "statsInboundUplink":    True,
            "statsOutboundDownlink": True, "statsOutboundUplink":   True
        },
        "levels": {"0": {"statsUserDownlink": True, "statsUserUplink": True}}
    },
    "observatory": {
        "subjectSelector":   tags,
        "probeURL":          "https://www.google.com/generate_204",
        "probeInterval":     "5s",
        "enableConcurrency": False
    },
    "api": {
        "tag": "api",
        "services": ["StatsService", "HandlerService", "LoggerService", "RoutingService"]
    },
    "stats": {},
    "metrics": {"listen": "127.0.0.1:11111", "tag": "metrics_out"}
}

with open("$FINAL_CONFIG", 'w') as f:
    json.dump(config, f, indent=2)

print(f"  Outbounds : {len(tags)}")
print(f"  Tags      : {', '.join(tags)}")
print(f"  Fallback  : {tags[0]}")
PYEOF

# Quick JSON validity check
python3 -c "import json; json.load(open('$FINAL_CONFIG'))"
ok "config.json is valid JSON"
cp "$FINAL_CONFIG" "$SAVE_CONFIG"
ok "Config also saved to $SAVE_CONFIG"

# =============================================================================
# STEP 6 — optionally validate with xray and deploy
# =============================================================================
if command -v xray &>/dev/null; then
    log "Running xray config test..."
    if xray run -test -config "$FINAL_CONFIG" 2>&1 | grep -q "Configuration OK"; then
        ok "Xray config test passed"
    else
        warn "Xray test had warnings (may still be OK):"
        xray run -test -config "$FINAL_CONFIG" 2>&1 | tail -5
    fi
fi

echo ""
echo -e "${BOLD}Generated:${NC} $FINAL_CONFIG"
echo ""

if [[ "${1:-}" == "--deploy" ]]; then
    log "Deploying..."
    BACKUP="${OUTPUT_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
    [ -f "$OUTPUT_CONFIG" ] && sudo cp "$OUTPUT_CONFIG" "$BACKUP" && ok "Backup: $BACKUP"
    sudo cp "$FINAL_CONFIG" "$OUTPUT_CONFIG"
    ok "Config deployed to $OUTPUT_CONFIG"
    sudo systemctl restart xray
    sleep 2
    sudo systemctl is-active xray && ok "Xray is running" || warn "Check: journalctl -u xray -n 20"
else
    echo -e "${YELLOW}To deploy:${NC}"
    echo -e "  sudo cp $FINAL_CONFIG $OUTPUT_CONFIG"
    echo -e "  sudo systemctl restart xray"
    echo ""
    echo -e "${YELLOW}Or re-run with:${NC}  $0 --deploy"
fi