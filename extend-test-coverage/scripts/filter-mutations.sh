#!/usr/bin/env bash
# filter-mutations.sh — Parse mutation.json and output a structured summary
# of surviving/no-coverage mutants grouped by file.
#
# Usage: bash filter-mutations.sh <mutation.json>
# Output: JSON summary printed to stdout

set -euo pipefail

MUTATION_FILE="${1:-reports/mutation/mutation.json}"

if [[ ! -f "$MUTATION_FILE" ]]; then
  echo "ERROR: $MUTATION_FILE not found." >&2
  exit 1
fi

node - "$MUTATION_FILE" << 'EOF'
const fs = require('fs');
const path = require('path');

const raw = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

const STATUS_FILTER = new Set(['Survived', 'NoCoverage']);

// Stryker JSON schema: { files: { [path]: { mutants: [...] } } }
const files = raw.files || {};

const byFile = {};
let totalMutants = 0;
let killedCount = 0;
let survivedCount = 0;
let noCoverageCount = 0;
let timeoutCount = 0;

for (const [filePath, fileData] of Object.entries(files)) {
  const relPath = path.relative(process.cwd(), path.resolve(filePath));
  const mutants = fileData.mutants || [];

  totalMutants += mutants.length;

  const relevant = mutants.filter(m => STATUS_FILTER.has(m.status));

  mutants.forEach(m => {
    if (m.status === 'Killed') killedCount++;
    else if (m.status === 'Survived') survivedCount++;
    else if (m.status === 'NoCoverage') noCoverageCount++;
    else if (m.status === 'Timeout') timeoutCount++;
  });

  if (relevant.length === 0) continue;

  byFile[relPath] = relevant.map(m => ({
    id: m.id,
    status: m.status,
    mutatorName: m.mutatorName,
    description: m.description || m.replacement,
    location: {
      start: m.location?.start,
      end: m.location?.end,
    },
    original: m.original,
    replacement: m.replacement,
  }));
}

const mutationScore = totalMutants > 0
  ? Math.round(((killedCount + timeoutCount) / totalMutants) * 100)
  : 100;

const output = {
  summary: {
    mutationScore,
    total: totalMutants,
    killed: killedCount,
    survived: survivedCount,
    noCoverage: noCoverageCount,
    timeout: timeoutCount,
    scoreLabel: mutationScore >= 80 ? '✅ Good' : mutationScore >= 60 ? '⚠️ Needs improvement' : '❌ Poor',
  },
  survivingMutants: byFile,
};

process.stdout.write(JSON.stringify(output, null, 2) + '\n');
EOF
