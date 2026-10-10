#!/bin/sh
# Installs the permission probe into Baron's development folder, builds Baron.app and runs
# baron-uitest --permissions: Deny, Allow Once and Always Allow through the real prompt, then the install sheet.
# Takes over the mouse and keyboard. Results: UITests/results/permissions/permissions.md
set -eu
cd "$(dirname "$0")/.."
dev="$HOME/Library/Application Support/Baron/Development"
mkdir -p "$dev"
rm -rf "$dev/uitest-permission-probe"
# The probe would put a button on every selection, so remove it whatever happens.
trap 'rm -rf "$dev/uitest-permission-probe"' EXIT
cp -R UITests/fixtures/permission-probe "$dev/uitest-permission-probe"
scripts/build-app.sh >/dev/null
swift build --product baron-uitest >/dev/null
"$(swift build --show-bin-path)/baron-uitest" --permissions --out UITests/results/permissions
