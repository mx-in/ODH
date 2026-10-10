#!/bin/sh
# Builds Baron.app and baron-probe into macos/build/ and signs both.
#
# macOS ties the Accessibility grant to the code signature. Ad-hoc signatures
# change on every build, so the grant would be lost each time. We sign with a
# stable identity instead: BARON_SIGN_IDENTITY if set, otherwise the first
# "Apple Development" identity in the keychain.
#
# Usage: scripts/build-app.sh [debug|release]
set -eu

cd "$(dirname "$0")/.."
configuration="${1:-debug}"
out="build"
app="$out/Baron.app"

identity="${BARON_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)
fi
if [ -z "$identity" ]; then
    echo "warning: no signing identity found; falling back to ad-hoc signing." >&2
    echo "         The Accessibility grant will be lost on every rebuild." >&2
    identity="-"
fi

swift build -c "$configuration" --product Baron
swift build -c "$configuration" --product baron-probe
bin=$(swift build -c "$configuration" --show-bin-path)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$bin/Baron" "$app/Contents/MacOS/Baron"
# SwiftPM resource bundles, such as BaronRuntime's plugin prelude.
for bundle in "$bin"/*.bundle; do
    [ -d "$bundle" ] && cp -R "$bundle" "$app/Contents/Resources/"
done
cp "$bin/baron-probe" "$out/baron-probe"

codesign --force --options runtime --timestamp=none --sign "$identity" --identifier org.odh.baron.probe "$out/baron-probe"
codesign --force --options runtime --timestamp=none --sign "$identity" "$app"
codesign --verify --strict "$app"

echo "Built $app and $out/baron-probe (signed with: $identity)"
