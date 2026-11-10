#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache" --scratch-path "$PWD/.build"
app="$PWD/dist/FM Tactics Lab 0.4.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/TacticsLabMac "$app/Contents/MacOS/TacticsLabMac"
clang -arch arm64 -framework Foundation native/EngineLoadProbe.m -o "$app/Contents/MacOS/EngineLoadProbe"
codesign --force --sign - "$app/Contents/MacOS/EngineLoadProbe"
clang++ -std=c++17 -arch arm64 -framework Foundation -Wno-deprecated-declarations native/EngineRuntimeProbe.mm native/EngineABI_arm64.S -o "$app/Contents/MacOS/EngineRuntimeProbe"
codesign --force --sign - "$app/Contents/MacOS/EngineRuntimeProbe"
cp ../LICENSE "$app/Contents/Resources/UPSTREAM-LICENSE.txt"
swiftc -module-cache-path .build/ModuleCache scripts/Icon.swift -o .build/make-icon
.build/make-icon .build/TacticsLab.iconset
iconutil -c icns .build/TacticsLab.iconset -o "$app/Contents/Resources/TacticsLab.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TacticsLabMac</string>
<key>CFBundleIdentifier</key><string>local.fm-tactics-lab.mac</string>
<key>CFBundleName</key><string>FM 战术实验室</string>
<key>CFBundleIconFile</key><string>TacticsLab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Built: $app"
