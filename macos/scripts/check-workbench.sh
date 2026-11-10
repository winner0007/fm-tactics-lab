#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -O -parse-as-library -module-cache-path .build/ModuleCache -I .build/arm64-apple-macosx/release/Modules \
  .build/arm64-apple-macosx/release/TacticsCore.build/*.o \
  Sources/TacticsLabMac/OriginalMatchJob.swift scripts/CheckWorkbench.swift -o .build/checks/workbench-check
.build/checks/workbench-check "$@"
