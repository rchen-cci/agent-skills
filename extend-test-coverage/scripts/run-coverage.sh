#!/usr/bin/env bash
# run-coverage.sh — Run Vitest coverage scoped to specific source files.
#
# Usage: bash run-coverage.sh "<space-separated-source-file-paths>"
# Output: writes coverage/coverage-final.json and coverage/coverage-summary.json

set -euo pipefail

FILES="${1:-}"

if [[ -z "$FILES" ]]; then
  echo "Usage: run-coverage.sh \"<space-separated-source-file-paths>\"" >&2
  exit 1
fi

# Detect package manager
if [[ -f "pnpm-lock.yaml" ]]; then
  PM="pnpm"
elif [[ -f "yarn.lock" ]]; then
  PM="yarn"
else
  PM="npm"
fi

# Build --coverage.include args from file list
INCLUDE_ARGS=()
read -ra file_array <<< "$FILES"
for f in "${file_array[@]}"; do
  # Convert absolute path to relative for vitest pattern matching
  rel="${f#"$(pwd)/"}"
  INCLUDE_ARGS+=("--coverage.include=$rel")
done

echo "Running Vitest coverage for ${#file_array[@]} file(s)..." >&2
echo "Files: $FILES" >&2

# Run vitest with v8 coverage provider
# --run: no watch mode
# --coverage: enable coverage
# --coverage.provider=v8: use V8 (already configured, but explicit)
# --coverage.reporter=json,json-summary: write machine-readable output
$PM vitest run \
  --coverage \
  --coverage.provider=v8 \
  --coverage.reporter=json \
  --coverage.reporter=json-summary \
  --coverage.reporter=text \
  "${INCLUDE_ARGS[@]}" \
  2>&1 | tee /tmp/vitest-coverage-output.txt || true

# Verify output files exist
if [[ ! -f "coverage/coverage-final.json" ]]; then
  echo "ERROR: coverage/coverage-final.json not found after run." >&2
  echo "Vitest output:" >&2
  cat /tmp/vitest-coverage-output.txt >&2
  exit 1
fi

echo "Coverage report written to coverage/" >&2
echo "coverage/coverage-final.json" 
echo "coverage/coverage-summary.json"
