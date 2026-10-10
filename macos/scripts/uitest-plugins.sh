#!/bin/sh
# Builds the example plugins and Baron.app, puts the examples in Baron's development folder, and runs
# baron-uitest --plugins: both examples from the bar, in a text area in Safari. Takes over the mouse and keyboard.
# Results: UITests/results/plugins/plugins.md
set -eu
cd "$(dirname "$0")/.."
repo=$(cd .. && pwd)
dev="$HOME/Library/Application Support/Baron/Development"
mkdir -p "$dev"
for example in uppercase lookup; do
    (cd "$repo" && npm run build -w "examples/$example" >/dev/null)
    rm -rf "$dev/example-$example"
    mkdir -p "$dev/example-$example/dist"
    cp "$repo/examples/$example/manifest.json" "$dev/example-$example/"
    cp "$repo/examples/$example/dist/main.js" "$dev/example-$example/dist/"
done
scripts/build-app.sh >/dev/null
swift build --product baron-uitest >/dev/null
"$(swift build --show-bin-path)/baron-uitest" --plugins --out UITests/results/plugins
