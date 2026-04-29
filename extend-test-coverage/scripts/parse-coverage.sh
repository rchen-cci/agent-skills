#!/usr/bin/env bash
# parse-coverage.sh — Parse coverage-final.json and output uncovered gaps as JSON.
#
# Usage: bash parse-coverage.sh <coverage-final.json> [filter-files...]
# Output: JSON array of coverage gap objects, printed to stdout

set -euo pipefail

COVERAGE_FILE="${1:-coverage/coverage-final.json}"
shift || true
FILTER_FILES=("$@")

if [[ ! -f "$COVERAGE_FILE" ]]; then
  echo "ERROR: $COVERAGE_FILE not found." >&2
  exit 1
fi

# Requires node (always available in JS projects)
node - "$COVERAGE_FILE" "${FILTER_FILES[@]}" << 'EOF'
const fs = require('fs');
const path = require('path');

const coverageFile = process.argv[2];
const filterFiles = process.argv.slice(3);

const coverage = JSON.parse(fs.readFileSync(coverageFile, 'utf8'));

const gaps = [];

for (const [filePath, data] of Object.entries(coverage)) {
  // If filter files specified, only process those
  if (filterFiles.length > 0) {
    const relPath = path.relative(process.cwd(), filePath);
    const absPath = path.resolve(filePath);
    const matches = filterFiles.some(f => 
      f === filePath || f === relPath || f === absPath ||
      absPath.endsWith(f) || relPath.endsWith(f)
    );
    if (!matches) continue;
  }

  const uncoveredLines = [];
  const uncoveredBranches = [];
  const uncoveredFunctions = [];

  // Uncovered statements (proxy for lines)
  if (data.s) {
    const statementMap = data.statementMap || {};
    for (const [key, count] of Object.entries(data.s)) {
      if (count === 0 && statementMap[key]) {
        const loc = statementMap[key];
        const line = loc.start?.line;
        if (line && !uncoveredLines.includes(line)) {
          uncoveredLines.push(line);
        }
      }
    }
  }

  // Uncovered branches
  if (data.b) {
    const branchMap = data.branchMap || {};
    for (const [key, counts] of Object.entries(data.b)) {
      counts.forEach((count, idx) => {
        if (count === 0) {
          const branch = branchMap[key];
          const branchId = `${key}-${idx}`;
          const line = branch?.loc?.start?.line || branch?.locations?.[idx]?.start?.line;
          uncoveredBranches.push({ id: branchId, line, type: branch?.type });
        }
      });
    }
  }

  // Uncovered functions
  if (data.f) {
    const fnMap = data.fnMap || {};
    for (const [key, count] of Object.entries(data.f)) {
      if (count === 0 && fnMap[key]) {
        uncoveredFunctions.push({
          name: fnMap[key].name,
          line: fnMap[key].loc?.start?.line,
        });
      }
    }
  }

  // Compute summary percentages
  const totalStmts = Object.keys(data.s || {}).length;
  const coveredStmts = Object.values(data.s || {}).filter(n => n > 0).length;
  const linePct = totalStmts > 0 ? Math.round((coveredStmts / totalStmts) * 100) : 100;

  const totalBranches = Object.values(data.b || {}).flat().length;
  const coveredBranches = Object.values(data.b || {}).flat().filter(n => n > 0).length;
  const branchPct = totalBranches > 0 ? Math.round((coveredBranches / totalBranches) * 100) : 100;

  const totalFns = Object.keys(data.f || {}).length;
  const coveredFns = Object.values(data.f || {}).filter(n => n > 0).length;
  const fnPct = totalFns > 0 ? Math.round((coveredFns / totalFns) * 100) : 100;

  if (uncoveredLines.length > 0 || uncoveredBranches.length > 0 || uncoveredFunctions.length > 0) {
    gaps.push({
      file: path.relative(process.cwd(), filePath),
      summary: { lines: linePct, branches: branchPct, functions: fnPct },
      uncoveredLines: uncoveredLines.sort((a, b) => a - b),
      uncoveredBranches,
      uncoveredFunctions,
    });
  }
}

if (gaps.length === 0) {
  process.stdout.write(JSON.stringify({ status: 'full_coverage', gaps: [] }, null, 2) + '\n');
} else {
  process.stdout.write(JSON.stringify({ status: 'gaps_found', gaps }, null, 2) + '\n');
}
EOF
