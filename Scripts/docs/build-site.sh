#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
site_output="$repo_root/.build/site"

# This directory contains only generated Pages output, never source documents.
rm -rf "$site_output"
mkdir -p "$site_output/recordings"
cp -R "$repo_root/Docs/Site/." "$site_output/"
for recording in dashboard choices feedback-light; do
  cp "$repo_root/Docs/Media/$recording.cast" "$site_output/recordings/"
  cp "$repo_root/Docs/Media/$recording.png" "$site_output/recordings/"
done
touch "$site_output/.nojekyll"
printf 'Built demo site: %s\n' "$site_output"
