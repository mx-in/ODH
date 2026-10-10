#!/bin/sh
# Builds examples/panel into Baron's development folder, builds Baron.app and runs baron-uitest --webviews:
# the result panel's placement, content, size, page↔plugin messages and close rules, in Safari.
# Needs the network (Youdao's dictionary). Takes over the mouse and keyboard. Results: UITests/results/webviews/webviews.md
set -eu
cd "$(dirname "$0")/.."
dev="$HOME/Library/Application Support/Baron/Development"
mkdir -p "$dev"
trap 'rm -rf "$dev/uitest-panel"' EXIT
(cd .. && npm run build -w examples/panel >/dev/null)
rm -rf "$dev/uitest-panel"
mkdir -p "$dev/uitest-panel"
cp -R ../examples/panel/manifest.json ../examples/panel/dist ../examples/panel/views "$dev/uitest-panel/"
scripts/build-app.sh >/dev/null
swift build --product baron-uitest >/dev/null
osascript -e 'quit app id "org.odh.baron"' >/dev/null 2>&1 || true
sleep 2
open build/Baron.app
sleep 3
"$(swift build --show-bin-path)/baron-uitest" --webviews --out UITests/results/webviews
