#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="dist/FM Tactics Lab 0.8.1.app"
archive="FM-Tactics-Lab-Mac-0.8.1-arm64.zip"
test -d "$app"
codesign --verify --deep --strict "$app"
cp 运行说明.txt dist/运行说明.txt
stage=$(mktemp -d "$PWD/.build/package-XXXXXX")
trap 'rm -rf "$stage"' EXIT
release="FM-Tactics-Lab-Mac-0.8.1"
mkdir "$stage/$release"
# Keep signed resources and symlinks; omit Finder metadata and extended attributes.
ditto --norsrc --noextattr --noqtn --noacl "$app" "$stage/$release/$(basename "$app")"
cp 运行说明.txt "$stage/$release/运行说明.txt"
codesign --verify --deep --strict "$stage/$release/$(basename "$app")"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$stage/$release" "$stage/raw.zip"
# ditto writes UTF-8 filename bytes without always setting the ZIP UTF-8 flag.
# Normalize that flag through zipfile while retaining permissions and symlinks.
.build/save-reader-venv/bin/python - "$stage/raw.zip" "dist/$archive" <<'PY'
import sys
from zipfile import ZipFile
with ZipFile(sys.argv[1]) as source, ZipFile(sys.argv[2], 'w') as target:
    for info in source.infolist():
        data=source.read(info)
        if not info.flag_bits & 0x800:
            info.filename=info.filename.encode('cp437').decode('utf8')
        target.writestr(info,data)
with ZipFile(sys.argv[2]) as result:
    assert result.testzip() is None
    names=result.namelist()
    assert len(names)==len(set(names))
    assert any(n.endswith('/运行说明.txt') for n in names)
    assert not any('__MACOSX' in n or '.DS_Store' in n for n in names)
PY
ditto -x -k "dist/$archive" "$stage/check"
codesign --verify --deep --strict "$stage/check/$release/$(basename "$app")"
(cd dist && shasum -a 256 "$archive" > SHA256.txt)
mkdir -p releases
cp dist/SHA256.txt releases/macos-v0.8.1-SHA256.txt
echo "Packaged: dist/$archive (ad hoc signed; not notarized)"
