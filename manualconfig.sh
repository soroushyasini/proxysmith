#!/usr/bin/env bash
# =============================================================================
# manualconfig.sh  —  Parse a hand-picked list of proxy URIs into config.json
#
# Usage:
#   bash manualconfig.sh                        # reads manualconfig.txt, writes manualconfig.json
#   bash manualconfig.sh my_proxies.txt         # custom input file
#   bash manualconfig.sh proxies.txt out.json   # custom input + output
#   bash manualconfig.sh --deploy               # parse + deploy + restart xray
#
# Input format (manualconfig.txt):
#   One URI per line. Blank lines and lines starting with # are ignored.
#   Accepted protocols: vless, vmess, trojan, ss, shadowsocks, tuic, hysteria2, hy2
#
# Output: manualconfig.json  (same directory as this script)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── defaults (overridable by positional args) ─────────────────────────────────
INPUT_FILE="$SCRIPT_DIR/manualconfig.txt"
OUTPUT_FILE="$SCRIPT_DIR/manualconfig.json"
DEPLOY=false

# ── arg parsing ───────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --deploy) DEPLOY=true ;;
        *.txt)    INPUT_FILE="$arg" ;;
        *.json)   OUTPUT_FILE="$arg" ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

OUTPUT_CONFIG="/usr/local/etc/xray/config.json"

# ── colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
DIM='\033[2m'; WHITE='\033[1;97m'; GREY='\033[0;90m'
log()  { echo -e "${CYAN}[*]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

# ── banner ────────────────────────────────────────────────────────────────────
echo -e "\033[0;31m"
cat << 'BANNER'
  ██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗███████╗███╗   ███╗██╗████████╗██╗  ██╗
  ██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝╚██╗ ██╔╝██╔════╝████╗ ████║██║╚══██╔══╝██║  ██║
  ██████╔╝██████╔╝██║   ██║ ╚███╔╝  ╚████╔╝ ███████╗██╔████╔██║██║   ██║   ███████║
  ██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗   ╚██╔╝  ╚════██║██║╚██╔╝██║██║   ██║   ██╔══██║
  ██║     ██║  ██║╚██████╔╝██╔╝ ██╗   ██║   ███████║██║ ╚═╝ ██║██║   ██║   ██║  ██║
  ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝     ╚═╝╚═╝   ╚═╝   ╚═╝  ╚═╝
BANNER
echo -e "\033[1;37m    Manual Config Builder  —  Skip the hunt, just parse and deploy\033[0m"
echo -e "\033[0;90m            ─────────────────────────────────────────────────────────────\033[0m"
echo -e "\033[0;90m            Author  :  Soroush Yasini\033[0m"
echo -e "\033[0;90m            Repo    :  https://github.com/soroushyasini/proxysmith\033[0m"
echo -e "\033[0;90m            ─────────────────────────────────────────────────────────────\033[0m"
echo -e "\033[0m"

# ── dep check (light — only xray-knife and python3 needed here) ───────────────
echo -e "${WHITE}  🔍  Checking dependencies${NC}"
echo -e "${GREY}  ──────────────────────────────────────────────────${NC}"
dep_ok=true
for cmd in xray-knife python3; do
    if command -v "$cmd" &>/dev/null; then
        printf "  ${GREEN}[✓]${NC}  %-14s ${DIM}%s${NC}\n" "$cmd" "$(command -v "$cmd")"
    else
        printf "  ${RED}[✗]${NC}  %-14s ${RED}not found${NC}\n" "$cmd"
        dep_ok=false
    fi
done
echo -e "${GREY}  ──────────────────────────────────────────────────${NC}\n"
[[ "$dep_ok" == true ]] || die "Missing dependencies. Run proxysmith.sh first — it will install everything."

# ── validate input file ───────────────────────────────────────────────────────
[[ -f "$INPUT_FILE" ]] || die "Input file not found: $INPUT_FILE
  Create it and add one proxy URI per line, e.g.:
    vless://uuid@host:port?...#remark
    ss://base64@host:port#remark
    trojan://password@host:port?...#remark"

# Count non-empty, non-comment lines
TOTAL_LINES=$(grep -cE '^[^#[:space:]]' "$INPUT_FILE" 2>/dev/null || echo 0)
[[ "$TOTAL_LINES" -gt 0 ]] || die "No valid URIs found in $INPUT_FILE  (blank or all lines are comments)"

echo -e "  ${BOLD}Input :${NC}  $INPUT_FILE  ${DIM}($TOTAL_LINES lines)${NC}"
echo -e "  ${BOLD}Output:${NC}  $OUTPUT_FILE"
echo ""

# ── parse URIs into outbound JSON ─────────────────────────────────────────────
log "Parsing $TOTAL_LINES URIs via xray-knife..."
echo ""

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
OUTBOUNDS_JSON="$WORK_DIR/outbounds.json"

python3 << PYEOF
import subprocess, json, sys, re

input_path     = "$INPUT_FILE"
outbounds_path = "$OUTBOUNDS_JSON"

# Accepted scheme prefixes
ACCEPTED = ('vless://', 'vmess://', 'trojan://', 'ss://', 'shadowsocks://',
            'tuic://', 'hysteria2://', 'hy2://', 'http://', 'https://',
            'socks://', 'socks5://')

lines_raw = open(input_path, encoding='utf-8', errors='replace').read().splitlines()

# Filter: skip blanks and comments
uris = []
skipped_fmt = []
for raw in lines_raw:
    line = raw.strip()
    if not line or line.startswith('#'):
        continue
    if any(line.lower().startswith(p) for p in ACCEPTED):
        uris.append(line)
    else:
        skipped_fmt.append(line)

if skipped_fmt:
    print(f"  Skipped {len(skipped_fmt)} lines with unrecognised scheme:")
    for s in skipped_fmt[:5]:
        print(f"    {DIM}{s[:80]}")
    if len(skipped_fmt) > 5:
        print(f"    ... and {len(skipped_fmt)-5} more")
    print()

print(f"  Processing {len(uris)} valid URIs...\n")

outbounds = []
tags = []
proto_counters = {}
errors = []

for uri in uris:
    proto = uri.split('://')[0].lower()
    # normalise ss alias
    if proto == 'shadowsocks':
        proto = 'ss'

    try:
        result = subprocess.run(
            ['xray-knife', 'parse', '-c', uri, '--json'],
            capture_output=True, text=True, timeout=10
        )
        raw = result.stdout.strip()
        if not raw:
            err_msg = result.stderr.strip()[:120] if result.stderr.strip() else "empty output"
            errors.append((uri, err_msg))
            print(f"  ${RED}[✗]${NC}  {uri[:70]}")
            print(f"       {DIM}{err_msg}{NC}")
            continue

        obj = json.loads(raw)

        # Handle full config wrapper vs bare outbound object
        if 'outbounds' in obj:
            ob = next(
                (o for o in obj['outbounds']
                 if o.get('protocol') not in ('freedom', 'blackhole')),
                None
            )
        elif 'protocol' in obj:
            ob = obj
        else:
            errors.append((uri, f"unexpected JSON shape: {list(obj.keys())}"))
            print(f"  ${RED}[✗]${NC}  {uri[:70]}")
            print(f"       ${DIM}unexpected JSON shape: {list(obj.keys())}{NC}")
            continue

        if not ob:
            errors.append((uri, "no usable outbound extracted"))
            print(f"  ${RED}[✗]${NC}  {uri[:70]}")
            continue

        proto_counters[proto] = proto_counters.get(proto, 0) + 1
        tag = f"{proto}_{proto_counters[proto]:02d}"
        ob['tag'] = tag

        outbounds.append(ob)
        tags.append(tag)

        # Try to show host for a friendly log line
        try:
            import urllib.parse
            parsed = urllib.parse.urlparse(uri.split('#')[0])
            host_info = f"{parsed.hostname}:{parsed.port}"
        except Exception:
            host_info = uri[len(proto)+3:][:40]

        remark = uri.split('#')[-1] if '#' in uri else ''
        remark_str = f"  {DIM}# {remark[:35]}{NC}" if remark else ''
        print(f"  ${GREEN}[✓]${NC}  {tag:<14}  {host_info:<35}{remark_str}")

    except subprocess.TimeoutExpired:
        errors.append((uri, "xray-knife parse timed out"))
        print(f"  ${RED}[✗]${NC}  {uri[:70]}")
        print(f"       ${YELLOW}timed out{NC}")
    except json.JSONDecodeError as e:
        errors.append((uri, f"JSON parse error: {e}"))
        print(f"  ${RED}[✗]${NC}  {uri[:70]}")
        print(f"       ${DIM}JSON error: {e}{NC}")
    except Exception as e:
        errors.append((uri, str(e)))
        print(f"  ${RED}[✗]${NC}  {uri[:70]}")
        print(f"       ${DIM}{e}{NC}")

print()
print(f"  Parsed  : {len(outbounds)} / {len(uris)} URIs OK")
if errors:
    print(f"  Failed  : {len(errors)}")
print()

with open(outbounds_path, 'w') as f:
    json.dump({'outbounds': outbounds, 'tags': tags}, f)

if not outbounds:
    print("ERROR: No outbounds could be parsed — nothing to write.", flush=True)
    sys.exit(1)
PYEOF

# ── check python exited cleanly ───────────────────────────────────────────────
[ -f "$OUTBOUNDS_JSON" ] || die "Parser produced no output file — check errors above"
PARSED_COUNT=$(python3 -c "import json; d=json.load(open('$OUTBOUNDS_JSON')); print(len(d['outbounds']))")
[[ "$PARSED_COUNT" -gt 0 ]] || die "All URIs failed to parse — nothing to write"
ok "$PARSED_COUNT outbound objects ready"

# ── assemble config.json ──────────────────────────────────────────────────────
log "Assembling config.json..."

python3 << PYEOF
import json

data      = json.load(open("$OUTBOUNDS_JSON"))
outbounds = data['outbounds']
tags      = data['tags']

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
            {"type": "field", "inboundTag": ["api"],                      "outboundTag": "api"},
            {"type": "field", "ip":         ["geoip:private"],            "outboundTag": "blocked"},
            {"type": "field", "domain":     ["geosite:category-ads-all"], "outboundTag": "blocked"},
            {"type": "field", "protocol":   ["bittorrent"],               "outboundTag": "blocked"},
            {"type": "field", "network":    "tcp,udp",                    "balancerTag":  "fast-tier"}
        ],
        "balancers": [{
            "tag":         "fast-tier",
            "selector":    tags,
            "fallbackTag": tags[0],
            "strategy":    {"type": "leastPing"}
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

with open("$OUTPUT_FILE", 'w') as f:
    json.dump(config, f, indent=2)

print(f"  Outbounds : {len(tags)}")
print(f"  Tags      : {', '.join(tags)}")
print(f"  Balancer  : leastPing  →  fallback: {tags[0]}")
PYEOF

# ── validate JSON ─────────────────────────────────────────────────────────────
python3 -c "import json; json.load(open('$OUTPUT_FILE'))" \
    && ok "JSON is valid" \
    || die "Output file failed JSON validation — this is a bug, please report it"

# ── optional xray syntax check ────────────────────────────────────────────────
if command -v xray &>/dev/null; then
    log "Running xray config test..."
    if xray run -test -config "$OUTPUT_FILE" 2>&1 | grep -q "Configuration OK"; then
        ok "Xray config test passed"
    else
        warn "Xray test had warnings (may still be OK):"
        xray run -test -config "$OUTPUT_FILE" 2>&1 | tail -5
    fi
fi

echo ""
echo -e "  ${BOLD}Written:${NC}  $OUTPUT_FILE"
echo ""

# ── deploy ────────────────────────────────────────────────────────────────────
if [[ "$DEPLOY" == true ]]; then
    log "Deploying to $OUTPUT_CONFIG..."
    BACKUP="${OUTPUT_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
    [ -f "$OUTPUT_CONFIG" ] && sudo cp "$OUTPUT_CONFIG" "$BACKUP" && ok "Backup: $BACKUP"
    sudo cp "$OUTPUT_FILE" "$OUTPUT_CONFIG"
    ok "Config deployed to $OUTPUT_CONFIG"
    sudo systemctl restart xray
    sleep 2
    sudo systemctl is-active xray \
        && ok "Xray is running" \
        || warn "Xray may have failed — check: journalctl -u xray -n 20"
else
    echo -e "${YELLOW}To deploy this config:${NC}"
    echo -e "  sudo cp $OUTPUT_FILE $OUTPUT_CONFIG"
    echo -e "  sudo systemctl restart xray"
    echo ""
    echo -e "${YELLOW}Or re-run with:${NC}  $0 --deploy"
fi
