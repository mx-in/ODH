#!/bin/sh
# Builds Baron.app with BaronPluginHost.xpc and runs baron-uitest --helper: a probe plugin's onInstall runs in the
# sandboxed helper, the helper is killed mid-hook, and a second install works in a new helper. Presses buttons
# through Accessibility only, so it works with the display asleep. Removes the probe afterwards.
# Results: UITests/results/helper/helper.md
set -eu
cd "$(dirname "$0")/.."
scripts/build-app.sh >/dev/null
swift build --product baron-uitest >/dev/null
osascript -e 'quit app id "org.odh.baron"' >/dev/null 2>&1 || true
sleep 2
plugins="$HOME/Library/Application Support/Baron/Plugins"
cleanup() {
    osascript -e 'quit app id "org.odh.baron"' >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$plugins/org.baron.uitest.helper-probe"
    python3 - "$plugins/installed.json" <<'PY'
import json, os, sys
p = sys.argv[1]
if os.path.exists(p):
    d = json.load(open(p)); d.pop("org.baron.uitest.helper-probe", None); json.dump(d, open(p, "w"), indent=2)
PY
    open build/Baron.app
}
trap cleanup EXIT
open build/Baron.app
sleep 3
probe="$(mktemp -d)/helper-probe.baronplugin"
(cd UITests/fixtures/helper-probe && zip -qr "$probe" manifest.json dist)
"$(swift build --show-bin-path)/baron-uitest" --helper "$probe" --out UITests/results/helper
