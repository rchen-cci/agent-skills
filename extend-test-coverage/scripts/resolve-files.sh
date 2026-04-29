#!/usr/bin/env bash
# resolve-files.sh — Expand a glob pattern or space-separated file list
# into absolute paths of source files (no test files, no node_modules).
#
# Usage: bash resolve-files.sh "<glob_or_paths>"
# Output: newline-separated absolute paths

set -euo pipefail

INPUT="${1:-}"

if [[ -z "$INPUT" ]]; then
  echo "Usage: resolve-files.sh \"<glob_pattern_or_space_separated_paths>\"" >&2
  exit 1
fi

EXCLUDE_PATTERNS=(
  "*.test.ts"
  "*.test.tsx"
  "*.spec.ts"
  "*.spec.tsx"
  "*.story.tsx"
  "*.stories.tsx"
  "*.d.ts"
  "node_modules"
)

resolve_path() {
  local path="$1"
  if [[ -f "$path" ]]; then
    realpath "$path"
  fi
}

is_excluded() {
  local file="$1"
  for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    case "$file" in
      *"$pattern"* | *node_modules*) return 0 ;;
    esac
  done
  return 1
}

results=()

# Check if input looks like a glob (contains *, ?, or {)
if [[ "$INPUT" =~ [\*\?\{] ]]; then
  while IFS= read -r -d '' file; do
    if ! is_excluded "$file"; then
      results+=("$(realpath "$file")")
    fi
  done < <(find . -type f \( -name "*.ts" -o -name "*.tsx" \) -not -path "*/node_modules/*" -print0 | \
            xargs -0 -I{} bash -c 'case "{}" in '"$INPUT"') && echo "{}" ;; esac' 2>/dev/null || true)

  # Simpler fallback using glob expansion
  if [[ ${#results[@]} -eq 0 ]]; then
    shopt -s globstar nullglob 2>/dev/null || true
    for file in $INPUT; do
      if [[ -f "$file" ]] && ! is_excluded "$file"; then
        results+=("$(realpath "$file")")
      fi
    done
  fi
else
  # Treat as space-separated paths
  read -ra paths <<< "$INPUT"
  for path in "${paths[@]}"; do
    if [[ -f "$path" ]] && ! is_excluded "$path"; then
      results+=("$(realpath "$path")")
    else
      echo "Warning: $path not found or excluded" >&2
    fi
  done
fi

if [[ ${#results[@]} -eq 0 ]]; then
  echo "No matching source files found." >&2
  exit 2
fi

# Deduplicate and print
printf '%s\n' "${results[@]}" | sort -u
