#!/bin/bash
set -euo pipefail

[[ $# -eq 1 && -x "$1/Contents/MacOS/cpsmart" ]] || {
    echo "usage: $0 /path/to/cpsmart.app" >&2
    exit 2
}
app_dir="$(cd "$1" && pwd)"
scripts="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/cpsmart-paste-windows.XXXXXX")"
trap 'rm -rf "$work"' EXIT
contents="$work/PasteReceiver.app/Contents"
mkdir -p "$contents/MacOS" "$work/isolated-home/store"
cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.cpsmart.tests.PasteReceiver</string>
<key>CFBundleExecutable</key><string>PasteReceiver</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
swiftc "$scripts/paste_window_receiver.swift" -o "$contents/MacOS/PasteReceiver"
codesign --force --sign - "$work/PasteReceiver.app"
touch "$work/report" "$work/errors"
open -W -n -a "$work/PasteReceiver.app" --stdout "$work/report" --stderr "$work/errors" \
    --args "$app_dir" "$work/isolated-home"
cat "$work/errors" >&2
cat "$work/report"
grep -Fxq "All paste window trials passed" "$work/report"
