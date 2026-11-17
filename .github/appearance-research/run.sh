#!/bin/bash
#
# Research for the pull request of the builder's words after the console in
# light mode, removed before it is merged: builds Probe.swift as an app,
# signed ad hoc, runs it for each way of making the console's window dark,
# and compares the console's picture of each with the app's own way's.
#
#     .github/appearance-research/run.sh WORK
#
set -euo pipefail

work="$1"
here="$(cd "$(dirname "$0")" && pwd)"
app="$work/Probe.app"
pictures="$work/pictures"
mkdir -p "$app/Contents/MacOS" "$pictures"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.cartouche.appearance-probe</string>
  <key>CFBundleExecutable</key><string>Probe</string>
  <key>CFBundleName</key><string>Probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
xcrun --sdk macosx swiftc -parse-as-library -O -o "$app/Contents/MacOS/Probe" "$here/Probe.swift"
codesign --force --sign - "$app"

for strategy in preferred windowFirst viewDuring viewAfter explicit; do
  echo "== $strategy"
  "$app/Contents/MacOS/Probe" "$strategy" "$pictures" 2>&1 || echo "✗ $strategy ended with $?"
done

echo "== the console of each, against the app's own"
for strategy in windowFirst viewDuring viewAfter explicit; do
  "$app/Contents/MacOS/Probe" --compare "$pictures/preferred-2-console.png" "$pictures/$strategy-2-console.png" || true
done
ls "$pictures"
