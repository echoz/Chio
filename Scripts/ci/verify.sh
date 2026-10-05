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

mkdir -p .build/ci-results
# Keep debug checks for library controls, domain values, raster layouts, and the
# focused examples. Run the dashboard's multi-screen workflows in release below:
# their five-second waits are not benchmarks of unoptimized rendering.
swift test --force-resolved-versions --jobs "${SWIFT_BUILD_JOBS:-2}" \
  --no-parallel --skip 'CreateAgentTests|DashboardPaletteTests|AgentReportInteractionTests' \
  --xunit-output .build/ci-results/debug.xml ${testing_flags[@]+"${testing_flags[@]}"}
swift test -c release --force-resolved-versions --jobs "${SWIFT_BUILD_JOBS:-2}" \
  --no-parallel --xunit-output .build/ci-results/release-all.xml ${testing_flags[@]+"${testing_flags[@]}"}
swift build --force-resolved-versions --jobs "${SWIFT_BUILD_JOBS:-2}" \
  -c release --product chio-dashboard
binary="$(swift build -c release --show-bin-path)/chio-dashboard"

for scenario in normal empty no-matches failed completed; do
  "$binary" --snapshot --width 100 --height 30 --scenario "$scenario" \
    > ".build/ci-results/$scenario.txt"
done
"$binary" --snapshot --width 36 --height 18 --light \
  > .build/ci-results/compact-light.txt
"$binary" --choices --snapshot --width 36 --height 18 \
    > .build/ci-results/choices-compact.txt
"$binary" --text-entry --snapshot --width 36 --height 18 \
    > .build/ci-results/text-entry-compact.txt
"$binary" --feedback --snapshot --width 36 --height 18 \
    > .build/ci-results/feedback-compact.txt
"$binary" --keyboard-help --snapshot --width 36 --height 18 \
    > .build/ci-results/keyboard-help-compact.txt
"$binary" --tabs --snapshot --width 36 --height 18 \
    > .build/ci-results/tabs-compact.txt
"$binary" --pagination --snapshot --width 36 --height 18 \
    > .build/ci-results/pagination-compact.txt
python3 Scripts/ci/terminal-smoke.py "$binary"
python3 Scripts/ci/terminal-smoke.py "$binary" --choices
python3 Scripts/ci/terminal-smoke.py "$binary" --text-entry
python3 Scripts/ci/terminal-smoke.py "$binary" --feedback
python3 Scripts/ci/terminal-smoke.py "$binary" --files
python3 Scripts/ci/terminal-smoke.py "$binary" --keyboard-help
python3 Scripts/ci/terminal-smoke.py "$binary" --tabs
python3 Scripts/ci/terminal-smoke.py "$binary" --pagination
