#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

capture_python="${CHIO_CAPTURE_PYTHON:-python3}"
if ! "$capture_python" -c 'import PIL' 2>/dev/null; then
  echo 'Capture images require Pillow. Set CHIO_CAPTURE_PYTHON to a Python interpreter with Pillow installed.' >&2
  exit 1
fi

testing_flags=()
if [[ "$(uname -s)" == Darwin ]]; then
  plugin="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
  if [[ -f "$plugin" ]]; then
    testing_flags=(-Xswiftc -load-plugin-library -Xswiftc "$plugin")
  fi
fi

directory="$PWD/.build/braille-map-spike"
mkdir -p "$directory"
CHIO_BRAILLE_CAPTURE_DIR="$directory" \
  swift test -c release --force-resolved-versions --jobs 2 --no-parallel \
    --filter BrailleMapSpikeTests ${testing_flags[@]+"${testing_flags[@]}"}
"$capture_python" Spikes/BrailleMaps/render-comparisons.py "$directory" "$@"
