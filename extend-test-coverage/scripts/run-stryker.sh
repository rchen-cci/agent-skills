#!/usr/bin/env bash
# run-stryker.sh — Set up and run Stryker mutation testing.
#
# Usage: bash run-stryker.sh "<space-separated-source-files>" "<space-separated-test-files>"
# Output: writes reports/mutation/mutation.json
#
# Known issues fixed in this script:
#   - Stryker CLI uses a positional config arg, not --configFile
#   - @stryker-mutator/vitest-runner must be listed explicitly in plugins[]
#   - Stryker's sandbox (.stryker-tmp) does NOT include node_modules, causing vitest
#     config deps to fail. inPlace: true bypasses the sandbox so the project's
#     node_modules remain accessible.
#   - coverageAnalysis: 'perTest' requires Vitest's related-file graph which breaks
#     in sandboxed mode. Use 'all' instead.
#   - vitest.related must be false when testFiles are specified explicitly.
#   - testFiles should use absolute paths for reliable resolution.

set -euo pipefail

SOURCE_FILES="${1:-}"
TEST_FILES="${2:-}"

if [[ -z "$SOURCE_FILES" || -z "$TEST_FILES" ]]; then
  echo "Usage: run-stryker.sh \"<source-files>\" \"<test-files>\"" >&2
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

# Check if Stryker is installed, install if missing
check_and_install() {
  local pkg="$1"
  if ! node -e "require('$pkg')" 2>/dev/null; then
    echo "Installing $pkg..." >&2
    $PM add -D "$pkg" 2>&1
  fi
}

echo "Checking Stryker dependencies..." >&2
check_and_install "@stryker-mutator/core"
check_and_install "@stryker-mutator/vitest-runner"

# Build JS arrays from space-separated paths.
# Always produces absolute paths — relative paths break when Stryker workers
# resolve them from a different working directory.
build_js_array() {
  local files="$1"
  local result="["
  read -ra arr <<< "$files"
  for i in "${!arr[@]}"; do
    local f="${arr[$i]}"
    # Make absolute if not already
    if [[ "$f" != /* ]]; then
      f="$(pwd)/$f"
    fi
    [[ $i -gt 0 ]] && result+=", "
    result+="\"$f\""
  done
  result+="]"
  echo "$result"
}

# For mutate[], relative paths are fine (resolved from cwd by Stryker core)
build_js_array_rel() {
  local files="$1"
  local result="["
  read -ra arr <<< "$files"
  for i in "${!arr[@]}"; do
    rel="${arr[$i]#"$(pwd)/"}"
    [[ $i -gt 0 ]] && result+=", "
    result+="\"$rel\""
  done
  result+="]"
  echo "$result"
}

MUTATE_ARRAY=$(build_js_array_rel "$SOURCE_FILES")
TEST_ARRAY=$(build_js_array "$TEST_FILES")

# Detect vitest config file (prefer .mts, fall back to .ts / .js)
VITEST_CONFIG="vitest.config.mts"
for cfg in vitest.config.mts vitest.config.ts vitest.config.js vite.config.ts vite.config.js; do
  if [[ -f "$cfg" ]]; then
    VITEST_CONFIG="$cfg"
    break
  fi
done

STRYKER_CONFIG="/tmp/stryker.config.$(date +%s).mjs"

cat > "$STRYKER_CONFIG" << HEREDOC
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
export default {
  testRunner: 'vitest',
  // Must be explicit — Stryker does not auto-discover the vitest runner plugin
  plugins: ['@stryker-mutator/vitest-runner'],
  mutate: $MUTATE_ARRAY,
  // Absolute paths for testFiles ensure correct resolution regardless of cwd
  testFiles: $TEST_ARRAY,
  vitest: {
    configFile: '$VITEST_CONFIG',
    // Must be false when testFiles are provided; otherwise Vitest's related-file
    // graph tries to discover tests and finds nothing in the sandbox
    related: false,
  },
  reporters: ['json', 'clear-text', 'progress'],
  jsonReporter: {
    fileName: 'reports/mutation/mutation.json',
  },
  // 'perTest' requires Vitest's related-file graph which breaks without node_modules
  // in the sandbox. 'all' runs every test for every mutant — slower but reliable.
  coverageAnalysis: 'all',
  // inPlace: true makes Stryker mutate files in the actual project directory
  // instead of copying to a sandbox. This is required because .stryker-tmp does
  // NOT include node_modules, causing vitest config deps (e.g. @vitejs/plugin-react)
  // to fail to resolve. A backup is created automatically and restored after the run.
  inPlace: true,
  thresholds: {
    high: 80,
    low: 60,
    break: null,
  },
  logLevel: 'info',
};
HEREDOC

echo "Stryker config written to $STRYKER_CONFIG" >&2
echo "Running Stryker against:" >&2
echo "  Sources: $SOURCE_FILES" >&2
echo "  Tests:   $TEST_FILES" >&2
echo "  Mode:    inPlace (no sandbox — uses project node_modules)" >&2

mkdir -p reports/mutation

# NOTE: Use positional arg, not --configFile flag (the flag does not exist in Stryker 8+)
npx stryker run "$STRYKER_CONFIG" 2>&1 | tee /tmp/stryker-output.txt || {
  EXIT_CODE=$?
  echo "Stryker exited with code $EXIT_CODE" >&2
  if [[ ! -f "reports/mutation/mutation.json" ]]; then
    echo "ERROR: mutation.json not produced." >&2
    echo "Stryker output:" >&2
    cat /tmp/stryker-output.txt >&2
    exit $EXIT_CODE
  fi
  # Non-zero exit from Stryker often just means thresholds not met — that's ok
}

rm -f "$STRYKER_CONFIG"

if [[ -f "reports/mutation/mutation.json" ]]; then
  echo "Mutation report written to reports/mutation/mutation.json" >&2
  echo "reports/mutation/mutation.json"
else
  echo "ERROR: reports/mutation/mutation.json not found." >&2
  exit 1
fi
