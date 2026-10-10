#!/bin/sh
# Times a first-time author: `baron create`, `npm install`, `npx baron dev`, then the new action on the bar
# (baron-uitest --bar-shows). Baron must be running; this turns on Developer mode and restarts it. The design's
# target is under two minutes. Takes over the mouse and keyboard. Results: UITests/results/author/author.md
set -eu
cd "$(dirname "$0")/.."
repo=$(cd .. && pwd)
now() { python3 -c 'import time; print(time.time())'; }
since() { python3 -c "print(round($(now) - $1, 1))"; }

scripts/build-app.sh >/dev/null
swift build --product baron-uitest >/dev/null
osascript -e 'quit app id "org.odh.baron"' >/dev/null 2>&1 || true
sleep 2
python3 - <<'PY'
import json, os, plistlib, subprocess
path = os.path.expanduser("~/Library/Preferences/org.odh.baron.plist")
settings = json.loads(plistlib.load(open(path, "rb"))["settings"]) if os.path.exists(path) else {}
settings["developerMode"] = True
subprocess.run(["defaults", "write", "org.odh.baron", "settings", "-data", json.dumps(settings).encode().hex()], check=True)
PY
open build/Baron.app
sleep 3

work=$(mktemp -d)
start=$(now)
(cd "$work" && bun "$repo/packages/cli/bin/baron.ts" create hello-baron --template action >/dev/null)
echo "baron create: $(since "$start") s"
(cd "$work/hello-baron" && npm install --silent >/dev/null)
echo "npm install: $(since "$start") s"
(cd "$work/hello-baron" && npx baron dev >"$work/dev.log" 2>&1) &
dev=$!
trap 'kill $dev 2>/dev/null || true' EXIT
until grep -q "Loaded\|error" "$work/dev.log" 2>/dev/null; do sleep 0.2; done
cat "$work/dev.log"
echo "baron dev loaded: $(since "$start") s"
"$(swift build --show-bin-path)/baron-uitest" --bar-shows "plugin:org.example.hello-baron/transform" --out UITests/results/author
echo "action on the bar and run: $(since "$start") s"
