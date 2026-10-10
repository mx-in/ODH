#!/bin/sh
# Installs the settings probe into Baron's development folder, builds Baron.app and runs baron-uitest --settings:
# a plugin settings page against a mock AnkiConnect. Takes over the mouse and keyboard.
# Results: UITests/results/settings/settings.md
set -eu
cd "$(dirname "$0")/.."
dev="$HOME/Library/Application Support/Baron/Development"
mkdir -p "$dev"
rm -rf "$dev/uitest-settings-probe"
trap 'rm -rf "$dev/uitest-settings-probe"' EXIT
cp -R UITests/fixtures/settings-probe "$dev/uitest-settings-probe"
scripts/build-app.sh >/dev/null
swift build --product baron-uitest >/dev/null
"$(swift build --show-bin-path)/baron-uitest" --settings --out UITests/results/settings
