#!/bin/sh
# Packs the uppercase example (1.0.0, and 1.1.0 adding clipboard.read) and a junk archive, builds Baron.app with
# its bundled plugin, and runs baron-uitest --install. Takes over the mouse and keyboard; it installs and removes
# the example plugins and resets the bar arrangement. Results: UITests/results/install/install.md
set -eu
cd "$(dirname "$0")/.."
repo=$(cd .. && pwd)
packages=$(mktemp -d)
work="$packages/uppercase"
cp -R "$repo/examples/uppercase" "$work"
rm -rf "$work/node_modules" "$work/dist"
ln -s "$repo/node_modules" "$work/node_modules"
(cd "$repo" && bun packages/cli/bin/baron.ts pack "$work" >/dev/null)
mv "$work"/org.baron.example.uppercase-1.0.0.baronplugin "$packages/uppercase-1.0.0.baronplugin"
python3 - "$work/manifest.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); m["version"] = "1.1.0"; m["permissions"] = m["permissions"] + ["clipboard.read"]
json.dump(m, open(p, "w"), indent=4)
PY
(cd "$repo" && bun packages/cli/bin/baron.ts pack "$work" >/dev/null)
mv "$work"/org.baron.example.uppercase-1.1.0.baronplugin "$packages/uppercase-1.1.0.baronplugin"
printf 'not a zip' > "$packages/junk.baronplugin"
scripts/build-app.sh >/dev/null
swift build --product baron-uitest >/dev/null
"$(swift build --show-bin-path)/baron-uitest" --install "$packages" --out UITests/results/install
