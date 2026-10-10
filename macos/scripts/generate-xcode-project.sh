#!/bin/sh
# Regenerates Xcode/Baron.xcodeproj from Xcode/project.yml.
# Uses `xcodegen` from PATH, or XCODEGEN=/path/to/xcodegen (https://github.com/yonaskolb/XcodeGen).
set -eu
cd "$(dirname "$0")/../Xcode"
"${XCODEGEN:-xcodegen}" generate --spec project.yml
