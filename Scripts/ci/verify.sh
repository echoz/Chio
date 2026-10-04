#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

swift --version
testing_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  # Some Apple 6.4 toolchains do not discover their installed Testing macros.
  plugin="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
  if [[ -f "$plugin" ]]; then
    testing_flags=(-Xswiftc -load-plugin-library -Xswiftc "$plugin")
  fi
fi

swift test --force-resolved-versions --jobs "${SWIFT_BUILD_JOBS:-2}" \
  --no-parallel ${testing_flags[@]+"${testing_flags[@]}"}
swift build --force-resolved-versions --jobs "${SWIFT_BUILD_JOBS:-2}" \
  -c release --product chio-dashboard
binary="$(swift build -c release --show-bin-path)/chio-dashboard"

mkdir -p .build/ci-results
for scenario in normal empty no-matches failed completed; do
  "$binary" --snapshot --width 100 --height 30 --scenario "$scenario" \
    > ".build/ci-results/$scenario.txt"
done
"$binary" --snapshot --width 36 --height 18 --light \
  > .build/ci-results/compact-light.txt
python3 Scripts/ci/terminal-smoke.py "$binary"
