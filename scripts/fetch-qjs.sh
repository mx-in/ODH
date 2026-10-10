#!/bin/sh
# Downloads QuickJS-NG's qjs, the second engine Baron plugins are tested on, into .tools/qjs.
# Pinned to one release; the checksum stops a changed download from running.
set -eu

VERSION=v0.17.0
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) ASSET=qjs-darwin-arm64 SHA256=8be3ddfe3397d2e692e4e1e8972ee9d032a0a580505d2f8b4ea528cf1b651c11 ;;
    Darwin-x86_64) ASSET=qjs-darwin-x86_64 SHA256=9e5e101b4fd13cda3204222ca9f8be35412c41dcdef3745829633b7a67245412 ;;
    Linux-x86_64) ASSET=qjs-linux-x86_64 SHA256=0bfc02511a9f549c28b53880d988fc7cd5d361e90c5e8afdfcd7dc6774ceace5 ;;
    Linux-aarch64) ASSET=qjs-linux-aarch64 SHA256=3372133484edf50a69f3c67903af41206d22a061e930e3cfb63269272ef56d2e ;;
    *) echo "fetch-qjs: no pinned qjs for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET="$ROOT/.tools/qjs"
if [ -x "$TARGET" ] && [ "$("$TARGET" -e 'print(1)' 2>/dev/null)" = "1" ] && [ -f "$TARGET.$VERSION" ]; then
    exit 0
fi

mkdir -p "$ROOT/.tools"
TMP="$TARGET.download"
curl -fsSL -o "$TMP" "https://github.com/quickjs-ng/quickjs/releases/download/$VERSION/$ASSET"
ACTUAL=$(shasum -a 256 "$TMP" | awk '{print $1}')
if [ "$ACTUAL" != "$SHA256" ]; then
    rm -f "$TMP"
    echo "fetch-qjs: checksum mismatch for $ASSET ($ACTUAL)" >&2
    exit 1
fi
chmod +x "$TMP"
mv "$TMP" "$TARGET"
rm -f "$TARGET".v*
touch "$TARGET.$VERSION"
echo "fetch-qjs: installed qjs $VERSION in .tools/"
