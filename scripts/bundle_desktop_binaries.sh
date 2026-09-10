#!/usr/bin/env bash
# Copies the pre-built Go pipeline binary into the Flutter Linux release
# bundle, at the path DesktopPipelineService expects (§7 of the desktop
# port handoff doc). Run this AFTER `flutter build linux --release`.
#
# Usage: ./scripts/bundle_desktop_binaries.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/app/linux/bin/proxysmith-pipeline-linux-amd64"
DEST_DIR="$REPO_ROOT/app/build/linux/x64/release/bundle/bin"
if [[ ! -f "$SRC" ]]; then
  echo "error: $SRC not found. Build it first (see app/linux/bin/README.md)." >&2
  exit 1
fi

if [[ ! -d "$(dirname "$DEST_DIR")" ]]; then
  echo "error: $(dirname "$DEST_DIR") not found. Run 'flutter build linux --release' first." >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST_DIR/"
chmod +x "$DEST_DIR/proxysmith-pipeline-linux-amd64"
echo "Copied to $DEST_DIR/proxysmith-pipeline-linux-amd64"
