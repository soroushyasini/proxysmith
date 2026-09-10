#!/usr/bin/env bash
# Build a validated Xray config from a local list of proxy URIs.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="$SCRIPT_DIR/manualconfig.txt"
OUTPUT_FILE="$SCRIPT_DIR/manualconfig.json"
OUTPUT_CONFIG="/usr/local/etc/xray/config.json"
TEST_URL="https://cp.cloudflare.com/generate_204"
DEPLOY=false

usage() {
  printf 'usage: %s [--deploy] [input.txt] [output.json]\n' "$0" >&2
}

for argument in "$@"; do
  case "$argument" in
    --deploy) DEPLOY=true ;;
    *.txt) INPUT_FILE="$argument" ;;
    *.json) OUTPUT_FILE="$argument" ;;
    *) usage; exit 2 ;;
  esac
done

log() { printf '[*] %s\n' "$*"; }
ok() { printf '[+] %s\n' "$*"; }
die() { printf '[!] %s\n' "$*" >&2; exit 1; }

for command_name in xray-knife xray python3; do
  command -v "$command_name" >/dev/null 2>&1 || die "Missing required command: $command_name"
done
[[ -f "$INPUT_FILE" ]] || die "Input file does not exist: $INPUT_FILE"
[[ -r "$INPUT_FILE" ]] || die "Input file is not readable: $INPUT_FILE"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/proxysmith-manual.XXXXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
OUTBOUNDS_JSON="$WORK_DIR/outbounds.json"
FINAL_CONFIG="$WORK_DIR/config.json"

log "Parsing the local proxy list"
python3 - "$INPUT_FILE" "$OUTBOUNDS_JSON" <<'PY'
import json
import os
import subprocess
import sys
from urllib.parse import urldefrag, urlsplit

input_path, output_path = sys.argv[1:]
maximum_file_bytes = 10 * 1024 * 1024
maximum_line_bytes = 64 * 1024
accepted = {"vless", "vmess", "trojan", "ss", "shadowsocks", "hysteria2", "hy2"}

if os.path.getsize(input_path) > maximum_file_bytes:
    raise SystemExit("Input exceeds the 10 MiB safety limit")

unique = {}
unsupported = malformed = duplicates = 0
with open(input_path, encoding="utf-8", errors="strict") as source:
    for raw in source:
        if len(raw.encode("utf-8")) > maximum_line_bytes:
            raise SystemExit("Input contains a line longer than 64 KiB")
        uri = raw.strip()
        if not uri or uri.startswith("#"):
            continue
        try:
            scheme = urlsplit(uri).scheme.lower()
        except ValueError:
            malformed += 1
            continue
        if scheme not in accepted:
            unsupported += 1
            continue
        identity = urldefrag(uri).url
        if identity in unique:
            duplicates += 1
            continue
        unique[identity] = uri

outbounds, tags, counters = [], [], {}
failed = 0
for uri in unique.values():
    scheme = urlsplit(uri).scheme.lower()
    protocol = "ss" if scheme == "shadowsocks" else scheme
    completed = subprocess.run(
        ["xray-knife", "parse", "-c", uri, "--json"],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        failed += 1
        continue
    try:
        parsed = json.loads(completed.stdout)
        candidates = parsed.get("outbounds", []) if "outbounds" in parsed else [parsed]
        outbound = next(
            item for item in candidates
            if item.get("protocol") not in {"freedom", "blackhole"}
        )
    except (json.JSONDecodeError, KeyError, StopIteration, TypeError):
        failed += 1
        continue
    counters[protocol] = counters.get(protocol, 0) + 1
    tag = f"{protocol}_{counters[protocol]:02d}"
    outbound["tag"] = tag
    outbounds.append(outbound)
    tags.append(tag)

if not outbounds:
    raise SystemExit("No supported URI could be converted to an Xray outbound")

with open(output_path, "w", encoding="utf-8") as destination:
    json.dump({"outbounds": outbounds, "tags": tags}, destination)

print(
    f"Accepted {len(outbounds)} unique entries; "
    f"skipped {duplicates} duplicates, {unsupported} unsupported, "
    f"{malformed} malformed, and {failed} parser failures"
)
PY

python3 - "$OUTBOUNDS_JSON" "$FINAL_CONFIG" "$TEST_URL" <<'PY'
import json
import sys

source_path, destination_path, test_url = sys.argv[1:]
with open(source_path, encoding="utf-8") as source:
    data = json.load(source)
outbounds, tags = data["outbounds"], data["tags"]
outbounds += [
    {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}},
    {"tag": "blocked", "protocol": "blackhole", "settings": {}},
]
config = {
    "log": {"loglevel": "warning", "error": "/var/log/xray/error.log"},
    "inbounds": [{
        "listen": "127.0.0.1",
        "port": 10808,
        "protocol": "socks",
        "settings": {"auth": "noauth", "udp": True},
    }],
    "outbounds": outbounds,
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"},
            {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "blocked"},
            {"type": "field", "protocol": ["bittorrent"], "outboundTag": "blocked"},
            {"type": "field", "network": "tcp,udp", "balancerTag": "fast-tier"},
        ],
        "balancers": [{
            "tag": "fast-tier",
            "selector": tags,
            "fallbackTag": tags[0],
            "strategy": {"type": "leastPing"},
        }],
    },
    "observatory": {
        "subjectSelector": tags,
        "probeURL": test_url,
        "probeInterval": "5s",
        "enableConcurrency": False,
    },
}
with open(destination_path, "w", encoding="utf-8") as destination:
    json.dump(config, destination, indent=2)
PY

log "Validating the generated configuration with Xray"
xray run -test -config "$FINAL_CONFIG" || die "Xray rejected the generated configuration; nothing was written"

OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
mkdir -p -- "$OUTPUT_DIR"
install -m 0600 "$FINAL_CONFIG" "${OUTPUT_FILE}.new"
mv -- "${OUTPUT_FILE}.new" "$OUTPUT_FILE"
ok "Validated configuration written to $OUTPUT_FILE"

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
  printf 'Re-run with --deploy after reviewing %s\n' "$OUTPUT_FILE"
fi
