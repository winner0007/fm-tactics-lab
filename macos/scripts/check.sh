#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
# Run identical core cases without requiring the full Xcode XCTest framework.
swiftc -O -parse-as-library -module-name TacticsMacChecks -module-cache-path .build/ModuleCache \
  Sources/TacticsCore/*.swift Tests/TacticsCoreTests/*.swift -o .build/checks/core-check
.build/checks/core-check
