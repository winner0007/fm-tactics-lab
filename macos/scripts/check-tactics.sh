#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
swiftc -O -parse-as-library -module-cache-path .build/ModuleCache -I .build/arm64-apple-macosx/release/Modules \
  .build/arm64-apple-macosx/release/TacticsCore.build/*.o \
  Sources/TacticsLabMac/OriginalMatchJob.swift Sources/TacticsLabMac/TacticGenerationJob.swift \
  scripts/CheckTactics.swift -o .build/checks/tactics-check
.build/checks/tactics-check "$@"
