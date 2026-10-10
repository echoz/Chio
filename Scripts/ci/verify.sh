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
# Check the real transport and online lifecycle before the longer composition
# suites. A failed test executable does not stop SwiftPM running other targets.
swift test --force-resolved-versions --jobs "${SWIFT_BUILD_JOBS:-2}" \
  --no-parallel --filter 'MapHTTPClientTests|OnlineMapInteractionTests' \
  --xunit-output .build/ci-results/online-preflight.xml ${testing_flags[@]+"${testing_flags[@]}"}
# Keep debug checks for library controls, domain values, raster layouts, and the
# focused examples. Run dashboard, inbox and diff compositions in release below:
# their five-second waits are not benchmarks of unoptimized rendering.
release_only_workflows='CreateAgentTests|DashboardPaletteTests|AgentReportInteractionTests'
release_only_workflows+='|DiffExampleTests/(hunkWorkflow|longSourceAndFiles)'
release_only_workflows+='|InboxExampleTests/(compactLaunchAndWideResize|filteringAndQueues|presentationAndReader|pendingReaderIsolation|pendingReaderCancellation)'
swift test --force-resolved-versions --jobs "${SWIFT_BUILD_JOBS:-2}" \
  --no-parallel --skip "$release_only_workflows" \
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
"$binary" --viewport --snapshot --width 36 --height 18 \
    > .build/ci-results/viewport-compact.txt
"$binary" --tree --snapshot --width 36 --height 18 \
    > .build/ci-results/tree-compact.txt
"$binary" --forms --snapshot --width 36 --height 18 \
    > .build/ci-results/forms-compact.txt
"$binary" --timers --snapshot --width 36 --height 18 \
    > .build/ci-results/timers-compact.txt
"$binary" --metrics --snapshot --width 36 --height 18 \
    > .build/ci-results/metrics-compact.txt
"$binary" --inbox --snapshot --width 36 --height 18 \
    > .build/ci-results/inbox-compact.txt
"$binary" --diff --snapshot --width 36 --height 18 \
    > .build/ci-results/diff-compact.txt
"$binary" --diff --snapshot --width 100 --height 30 \
    > .build/ci-results/diff-wide.txt
python3 Scripts/ci/terminal-smoke.py "$binary"
python3 Scripts/ci/terminal-smoke.py "$binary" --choices
python3 Scripts/ci/terminal-smoke.py "$binary" --text-entry
python3 Scripts/ci/terminal-smoke.py "$binary" --feedback
python3 Scripts/ci/terminal-smoke.py "$binary" --files
python3 Scripts/ci/terminal-smoke.py "$binary" --keyboard-help
python3 Scripts/ci/terminal-smoke.py "$binary" --tabs
python3 Scripts/ci/terminal-smoke.py "$binary" --pagination
python3 Scripts/ci/terminal-smoke.py "$binary" --viewport
python3 Scripts/ci/terminal-smoke.py "$binary" --tree
python3 Scripts/ci/terminal-smoke.py "$binary" --forms
python3 Scripts/ci/terminal-smoke.py "$binary" --timers
python3 Scripts/ci/terminal-smoke.py "$binary" --metrics
python3 Scripts/ci/terminal-smoke.py "$binary" --inbox
python3 Scripts/ci/terminal-smoke.py "$binary" --diff

# Public map contracts run with the test targets above. Exercise the local map
# example separately from the dashboard, including fixture provenance and raw input.
python3 Scripts/maps/prepare-fixtures.py --verify
swift build --force-resolved-versions --jobs "${SWIFT_BUILD_JOBS:-2}" \
  -c release --product chio-maps
map_binary="$(swift build -c release --show-bin-path)/chio-maps"
python3 Scripts/maps/terminal-probe.py "$map_binary" --output-dir .build/ci-results/maps

# Real HTTP acquisition against retained bytes, never a live provider in CI.
python3 Scripts/maps/online-fixture-server.py --verify
online_directory=.build/ci-results/maps/online
mkdir -p "$online_directory"
rm -f "$online_directory/ready.json"
python3 Scripts/maps/online-fixture-server.py \
  --config-file "$online_directory/source.json" --ready-file "$online_directory/ready.json" \
  > "$online_directory/server.log" 2>&1 &
online_server_pid=$!
stop_online_server() {
  kill "$online_server_pid" 2>/dev/null || true
  wait "$online_server_pid" 2>/dev/null || true
}
trap stop_online_server EXIT
for attempt in {1..50}; do
  [[ -s "$online_directory/ready.json" ]] && break
  kill -0 "$online_server_pid" 2>/dev/null || { cat "$online_directory/server.log"; exit 1; }
  sleep 0.1
done
[[ -s "$online_directory/ready.json" ]] || { echo "Online fixture did not start within five seconds"; exit 1; }
python3 Scripts/maps/terminal-probe.py "$map_binary" \
  --online-source "$online_directory/source.json" --output-dir "$online_directory"
stop_online_server
trap - EXIT

# Separate executable launches prove disk reuse and cooperative ownership.
python3 -B Scripts/maps/cache-probe.py "$map_binary" --output-dir .build/ci-results/maps/cache
python3 -B Scripts/maps/pack-probe.py "$map_binary" --output-dir .build/ci-results/maps/pack
