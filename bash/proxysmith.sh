#!/usr/bin/env bash
# =============================================================================
# proxysmith.sh  —  RomanLegioner daily config builder
# Requires: xray-knife (in PATH), python3, jq
# Usage:
#   bash proxysmith.sh            # generate only
#   bash proxysmith.sh --deploy   # generate + deploy + restart xray
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

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
DIM='\033[2m'; WHITE='\033[1;97m'; GREY='\033[0;90m'
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

# =============================================================================
# DEPENDENCY CHECKER
# Checks for all required tools; offers to install missing ones automatically.
# =============================================================================
check_and_install_deps() {
    echo -e "\n${WHITE}  🔍  Checking dependencies${NC}"
    echo -e "${GREY}  ──────────────────────────────────────────────────${NC}"

    local missing_apt=()
    local missing_manual=()
    local all_ok=true

    dep_status() {
        local name="$1" found="$2"
        if [[ "$found" == "yes" ]]; then
            printf "  ${GREEN}[✓]${NC}  %-18s ${DIM}%s${NC}\n" "$name" "$(command -v "$name" 2>/dev/null)"
        else
            printf "  ${RED}[✗]${NC}  %-18s ${YELLOW}%s${NC}\n" "$name" "$3"
            all_ok=false
        fi
    }

    command -v xray-knife &>/dev/null \
        && dep_status "xray-knife" "yes" \
        || { dep_status "xray-knife" "no" "not in PATH — needs manual install"; missing_manual+=("xray-knife"); }

    command -v xray &>/dev/null \
        && dep_status "xray" "yes" \
        || { dep_status "xray" "no" "not in PATH — needs manual install"; missing_manual+=("xray"); }

    command -v python3 &>/dev/null \
        && dep_status "python3" "yes" \
        || { dep_status "python3" "no" "will install via apt"; missing_apt+=("python3"); }

    command -v jq &>/dev/null \
        && dep_status "jq" "yes" \
        || { dep_status "jq" "no" "will install via apt"; missing_apt+=("jq"); }

    command -v wget &>/dev/null \
        && dep_status "wget" "yes" \
        || { dep_status "wget" "no" "will install via apt"; missing_apt+=("wget"); }

    command -v unzip &>/dev/null \
        && dep_status "unzip" "yes" \
        || { dep_status "unzip" "no" "will install via apt"; missing_apt+=("unzip"); }

    echo -e "${GREY}  ──────────────────────────────────────────────────${NC}\n"

    # All present → skip ahead
    if [[ "$all_ok" == true ]]; then
        ok "All dependencies satisfied."
        echo ""
        return 0
    fi

    # Print install plan
    if [[ ${#missing_apt[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}Will install via apt:${NC}  ${missing_apt[*]}"
        echo ""
    fi

    if [[ ${#missing_manual[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}Require a one-time download/install:${NC}"
        for tool in "${missing_manual[@]}"; do
            case "$tool" in
                xray-knife)
                    echo -e "\n    ${BOLD}xray-knife${NC}"
                    echo -e "    ${DIM}wget https://github.com/lilendian0x00/xray-knife/releases/latest/download/Xray-knife-linux-64.zip${NC}"
                    echo -e "    ${DIM}unzip → sudo mv xray-knife /usr/local/bin/ → chmod +x${NC}"
                    ;;
                xray)
                    echo -e "\n    ${BOLD}xray${NC}"
                    echo -e '    ${DIM}bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install${NC}'
                    ;;
            esac
        done
        echo ""
    fi

    read -rp "  Install missing dependencies now? [Y/n]  (Enter = yes): " do_install
    [[ "${do_install,,}" == "n" ]] && echo "" && die "Cannot proceed without required dependencies."
    echo ""

    # ── apt packages ──────────────────────────────────────────────────────────
    if [[ ${#missing_apt[@]} -gt 0 ]]; then
        log "apt-get update..."
        sudo apt-get update -qq || die "apt update failed"
        log "Installing: ${missing_apt[*]}"
        sudo apt-get install -y "${missing_apt[@]}" \
            || die "apt install failed — install manually and re-run"
        ok "Installed via apt: ${missing_apt[*]}"
        echo ""
    fi

    # ── xray-knife ────────────────────────────────────────────────────────────
    if [[ " ${missing_manual[*]} " == *" xray-knife "* ]]; then
        log "Downloading xray-knife (latest release)..."
        local tmp_dir
        tmp_dir=$(mktemp -d)

        wget -q --show-progress \
            "https://github.com/lilendian0x00/xray-knife/releases/latest/download/Xray-knife-linux-64.zip" \
            -O "$tmp_dir/xray-knife.zip" \
            || die "Download failed — check your internet connection"

        log "Extracting..."
        unzip -q "$tmp_dir/xray-knife.zip" -d "$tmp_dir" \
            || die "Unzip failed"

        # The binary may land with different names depending on release packaging
        local bin_path
        bin_path=$(find "$tmp_dir" -maxdepth 2 -type f -iname "xray-knife" | head -1)
        [[ -z "$bin_path" ]] && bin_path=$(find "$tmp_dir" -maxdepth 2 -type f -iname "Xray-knife" | head -1)
        [[ -z "$bin_path" ]] && die "Could not find xray-knife binary after unzip (files: $(ls "$tmp_dir"))"

        sudo mv "$bin_path" /usr/local/bin/xray-knife
        sudo chmod +x /usr/local/bin/xray-knife
        rm -rf "$tmp_dir"

        command -v xray-knife &>/dev/null \
            && ok "xray-knife installed → $(command -v xray-knife)" \
            || die "xray-knife install failed — binary not found in PATH after move"
        echo ""
    fi

    # ── xray ─────────────────────────────────────────────────────────────────
    if [[ " ${missing_manual[*]} " == *" xray "* ]]; then
        log "Installing xray via official installer script..."
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install \
            || die "xray install script failed — check output above"

        # Official installer puts xray at /usr/local/bin/xray
        command -v xray &>/dev/null \
            && ok "xray installed → $(command -v xray)" \
            || die "xray not found in PATH after install — check /usr/local/bin/"
        echo ""
    fi

    # ── final verification ────────────────────────────────────────────────────
    log "Final dependency check..."
    local final_ok=true
    for cmd in xray-knife xray python3 jq; do
        if command -v "$cmd" &>/dev/null; then
            printf "  ${GREEN}[✓]${NC}  %s\n" "$cmd"
        else
            printf "  ${RED}[✗]${NC}  %-14s  ${RED}still missing after install${NC}\n" "$cmd"
            final_ok=false
        fi
    done
    echo ""

    [[ "$final_ok" == true ]] || die "Some dependencies are still missing. Fix manually and re-run."
    ok "All dependencies ready."
    echo ""
}

check_and_install_deps

# ── INTERACTIVE SETUP ─────────────────────────────────────────────────────────
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

interactive_setup

# ─────────────────────────────────────────────────────────────────────────────
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
TOTAL=$(( $(wc -l < "$CSV") - 1 ))
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
top_n    = $TOP_N * 3
out_path = "$WORK_DIR/round1_winners.txt"

def uri_key(uri):
    try:
        base = uri.split('#')[0]
        parsed = urllib.parse.urlparse(base)
        return f"{parsed.scheme}:{parsed.hostname}:{parsed.port}"
    except Exception:
        return uri.split('#')[0]

with open(csv_path, encoding="latin-1", errors="replace") as raw_f:
    clean = (line.replace("\x00", "") for line in raw_f)
    reader = csv.DictReader(clean)
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

awk -F'\t' '{print $2}' "$WORK_DIR/round1_winners.txt" > "$WORK_DIR/round1_uris.txt"

CSV2="$WORK_DIR/results_round2.csv"
xray-knife http \
    -f "$WORK_DIR/round1_uris.txt" \
    --speedtest \
    --sort \
    --type csv \
    -o "$CSV2" \
    --thread "$TEST_THREADS" \
    --url "https://www.google.com/generate_204"

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

with open(csv_path, encoding="latin-1", errors="replace") as raw_f:
    clean = (line.replace("\x00", "") for line in raw_f)
    reader = csv.DictReader(clean)
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

with open(csv_path, encoding="latin-1", errors="replace") as raw_f:
    clean = (line.replace("\x00", "") for line in raw_f)
    reader = csv.DictReader(clean)
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

        obj = json.loads(raw)

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
