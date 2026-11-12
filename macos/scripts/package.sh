#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="dist/FM Tactics Lab 0.7.0.app"
archive="FM-Tactics-Lab-Mac-0.7.0-arm64.zip"
test -d "$app"
codesign --verify --deep --strict "$app"
cp 运行说明.txt dist/运行说明.txt
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$archive"
(cd dist && shasum -a 256 "$archive" > SHA256.txt)
echo "Packaged: dist/$archive (ad hoc signed; not notarized)"
