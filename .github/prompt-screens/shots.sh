#!/bin/bash
# Screenshots of nxnative's prompt that waits for more players and of its
# gear menu on an iPhone 17 Pro in the Simulator, without Cartouche's texts
# (up to 0.16.2) and with them, in each language. For PR #367 alone, removed
# before it merges. Usage: shots.sh OUT
set -euo pipefail
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
(cd "$HERE" && xcodegen generate --quiet)
UDID="$(python3 - <<'PY'
import json, subprocess
def listing(*args):
    return json.loads(subprocess.run(["xcrun", "simctl", "list", "-j", *args], check=True, capture_output=True, text=True).stdout)
def release(r):
    try:
        return tuple(int(n) for n in r.get("version", "0").split("."))
    except ValueError:
        return (0,)
runtimes = [r for r in listing("runtimes")["runtimes"] if r.get("isAvailable", True) and r.get("platform", "iOS") == "iOS"]
runtime = max(runtimes, key=lambda r: (release(r), -len(r["identifier"])))
models = [t for t in runtime.get("supportedDeviceTypes", []) if t.get("name", "").startswith("iPhone")]
wanted = next((t for t in models if t["name"] == "iPhone 17 Pro"), models[-1])
print(subprocess.run(["xcrun", "simctl", "create", "Prompt screens", wanted["identifier"], runtime["identifier"]],
                     check=True, capture_output=True, text=True).stdout.strip())
PY
)"
xcodebuild -project "$HERE/PromptScreens.xcodeproj" -scheme PromptScreens -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$OUT/../derived" build -quiet
APP="$(find "$OUT/../derived/Build/Products" -name PromptScreens.app -maxdepth 3 | head -1)"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"
ID=io.github.clabeuhtegrite.cartouche.promptscreens
shot() {
  local show=$1 texts=$2 language=$3
  xcrun simctl terminate "$UDID" "$ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$ID" -show "$show" -texts "$texts" -AppleLanguages "($language)" -AppleLocale "$language"
  sleep 6
  xcrun simctl io "$UDID" screenshot "$OUT/$show-$texts.png"
  echo "$show-$texts.png"
}
for show in prompt menu; do
  shot "$show" none en
  for language in fr es de en; do
    shot "$show" "$language" "$language"
  done
done
xcrun simctl spawn "$UDID" log show --last 5m --predicate 'eventMessage CONTAINS "prompt-screens"' --style compact > "$OUT/log.txt" 2>&1 || true
xcrun simctl shutdown "$UDID" || true
