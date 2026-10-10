#!/bin/sh
# Installs the context-probe and context-blind fixtures into Baron's development folder, builds Baron.app and runs
# baron-uitest --context in Safari, Chrome, Mail, Notes, Pages and TextEdit. Takes over the mouse and keyboard.
# Results: UITests/results/context/context.md
set -eu
cd "$(dirname "$0")/.."
dev="$HOME/Library/Application Support/Baron/Development"
mkdir -p "$dev"
# The fixtures would put two buttons on every selection, so remove them whatever happens.
trap 'rm -rf "$dev/uitest-context-probe" "$dev/uitest-context-blind"' EXIT
for fixture in context-probe context-blind; do
    rm -rf "$dev/uitest-$fixture"
    cp -R "UITests/fixtures/$fixture" "$dev/uitest-$fixture"
done
scripts/build-app.sh >/dev/null
swift build --product baron-uitest >/dev/null
osascript -e 'quit app id "org.odh.baron"' >/dev/null 2>&1 || true
sleep 2
open build/Baron.app
sleep 3
"$(swift build --show-bin-path)/baron-uitest" --context --out UITests/results/context
