---
name: extend-test-coverage
description: Analyzes test coverage gaps using Vitest v8 coverage, generates missing tests for uncovered code, then validates quality with Stryker mutation testing. Produces a filtered mutation report highlighting surviving mutants. Use when asked to improve test coverage, add missing tests, extend tests, check coverage gaps, eliminate dead tests, or when given file paths or glob patterns to test.
---

# Extend Test Coverage

Runs a 4-phase pipeline: **coverage analysis → test generation → mutation testing → report**.

## Inputs

The user provides one of:
- **File list**: explicit paths (e.g. `src/utils/format.ts src/hooks/useData.ts`)
- **Glob pattern**: e.g. `src/deploys/**/*.ts` (excluding test files)

## Phase 1 — Resolve Files

Run `scripts/resolve-files.sh` to expand input into a clean file list.

```bash
bash ~/.cursor/skills/extend-test-coverage/scripts/resolve-files.sh \
  "<glob_or_space_separated_paths>"
```

Output: newline-separated absolute paths to source files (no test files, no node_modules).

If the list is empty, stop and tell the user no matching source files were found.

## Phase 2 — Run Coverage

Run `scripts/run-coverage.sh` with the resolved file list.

```bash
bash ~/.cursor/skills/extend-test-coverage/scripts/run-coverage.sh \
  "<space-separated-file-paths>"
```

This runs `vitest run --coverage` scoped to those files and writes:
- `coverage/coverage-final.json` — per-file, per-line hit counts
- `coverage/coverage-summary.json` — summary percentages

Then run `scripts/parse-coverage.sh` to extract the gaps:

```bash
bash ~/.cursor/skills/extend-test-coverage/scripts/parse-coverage.sh \
  coverage/coverage-final.json
```

Output: a JSON array of coverage gaps, e.g.:

```json
[
  {
    "file": "src/utils/format.ts",
    "uncoveredLines": [14, 15, 22],
    "uncoveredBranches": ["14-1", "22-0"],
    "uncoveredFunctions": ["formatCurrency"]
  }
]
```

If all files are at 100% coverage, skip to Phase 4 (mutation testing on existing tests).

## Phase 3 — Generate Missing Tests

For each file with coverage gaps:

1. **Read the source file** to understand the uncovered code at the reported lines.
2. **Locate or create the test file**: `<filename>.test.ts` or `<filename>.test.tsx` in the same directory.
3. **Write targeted tests** covering:
   - Each uncovered function/method
   - Each uncovered branch (truthy AND falsy paths)
   - Each uncovered line group
4. **Run coverage again** on the updated test file to verify the gaps closed:
   ```bash
   bash ~/.cursor/skills/extend-test-coverage/scripts/run-coverage.sh "<file>"
   ```
   Iterate until the specific file reaches ≥90% line + branch coverage, or document why a line is intentionally unreachable.

**Test conventions for this repo:**
- Framework: **Vitest** with `globals: true`, `environment: jsdom`
- Imports: `import { describe, it, expect, vi, beforeEach } from 'vitest'`
- React: use `@testing-library/react` (`render`, `screen`, `fireEvent`, `waitFor`)
- Providers: check for a `renderWithProviders` in `~/test-utils` before wrapping manually
- Mocks: `vi.mock(...)` and `vi.fn()`
- File naming: `<SourceFile>.test.ts` or `<SourceFile>.test.tsx`

## Phase 4 — Mutation Testing

Run Stryker against the **newly created or modified test files** only.

```bash
bash ~/.cursor/skills/extend-test-coverage/scripts/run-stryker.sh \
  "<space-separated-source-files>" \
  "<space-separated-test-files>"
```

This script:
1. Checks for / installs `@stryker-mutator/core` and `@stryker-mutator/vitest-runner`
2. Writes a temp `stryker.config.mjs` scoped to the target files
3. Runs `npx stryker run`
4. Outputs `reports/mutation/mutation.json`

Then filter results:

```bash
bash ~/.cursor/skills/extend-test-coverage/scripts/filter-mutations.sh \
  reports/mutation/mutation.json
```

### Compute per-test kill counts and prune zero-kill tests

After Stryker produces `reports/mutation/mutation.json`, run this inline Python to:
1. Map each test ID → name (skipping `.stryker-tmp` sandbox duplicates)
2. Count how many mutants each test killed (via the `killedBy` array on each mutant)
3. Identify tests with 0 kills

```python
import json
from collections import defaultdict

with open('reports/mutation/mutation.json') as f:
    data = json.load(f)

# Build test ID → name (skip sandbox duplicates)
id_to_name = {}
for filepath, fdata in data.get('testFiles', {}).items():
    if '.stryker-tmp' in filepath:
        continue
    for t in fdata.get('tests', []):
        id_to_name[t['id']] = t['name']

# Count kills per test
kills = defaultdict(int)
for filepath, fdata in data.get('files', {}).items():
    for m in fdata.get('mutants', []):
        for tid in m.get('killedBy', []):
            kills[tid] += 1

# Print sorted by kill count descending
for tid, name in sorted(id_to_name.items(), key=lambda x: -kills.get(x[0], 0)):
    print(f"[{kills.get(tid, 0):2d} kills] {name}")

# Print zero-kill tests
zero = [name for tid, name in id_to_name.items() if kills.get(tid, 0) == 0]
print(f"\nZero-kill tests ({len(zero)}):")
for n in zero:
    print(f"  - {n}")
```

**Then remove zero-kill tests from the test file.** For each zero-kill test name, find the corresponding `it(...)` block in the test file and delete it (along with its surrounding blank lines). If a `describe(...)` block becomes empty after removal, delete the block too. Use `StrReplace` for precision — match enough surrounding context to uniquely identify each block.

## Phase 5 — Output Report

Format and present the report using the template in [OUTPUT_FORMAT.md](OUTPUT_FORMAT.md).

Show the user:
1. **Coverage delta** — before/after per file
2. **Tests generated** — list of new test cases added
3. **Mutation score** — overall %
4. **Per-test kill count** — table of surviving tests sorted by kills descending (include the count next to each test name)
5. **Removed tests** — list of zero-kill tests that were pruned and why
6. **Surviving mutants** — grouped by file, with code snippet + suggested fix
7. **Action items** — clear next steps if mutation score < 80%

## Error Handling

| Situation | Action |
|-----------|--------|
| No test runner found | Check `package.json` for vitest, offer to install |
| Stryker install fails | Suggest manual `pnpm add -D @stryker-mutator/core @stryker-mutator/vitest-runner` |
| File not in tsconfig | Note the file and skip; report it |
| Coverage already 100% | Skip Phase 3, go straight to mutation testing |
| Mutation score ≥ 80% | Report success, no action items needed |
| `run-coverage.sh` fails with "Unknown command: vitest" | The script ran from a directory without `pnpm-lock.yaml`. Run from the sub-project root (e.g. `web-ui/`). Also check whether `.npmrc` uses `${NPM_TOKEN}` — if so, pnpm silently exits in fresh shells. Work around by keeping the shell stateful: `cd` into the project directory in one call, then run `pnpm` commands in subsequent calls using the same shell session. |
| pnpm silently exits with code 1 and no output | Usually caused by `.npmrc` with an unset env var like `${NPM_TOKEN}`. The foreground shell session picks up the user's env, but background shells (fresh processes) do not. Fix: run commands in the **stateful foreground shell** (not backgrounded) after having already `cd`-ed to the right directory in a prior call. |
| Stryker "No tests were found" | The sandbox (`.stryker-tmp`) does not include `node_modules`, so vitest's config file cannot resolve its plugin dependencies (`@vitejs/plugin-react`, `vite-tsconfig-paths`, etc.). **Fix: add `inPlace: true` to the Stryker config.** This makes Stryker mutate files directly in the project (with a backup), bypassing the sandbox entirely and keeping `node_modules` accessible. |
| Stryker `error: unknown option '--configFile'` | The CLI changed: use a positional argument, not a flag. Run `npx stryker run /path/to/stryker.config.mjs` (no `--configFile`). |
| Stryker "Cannot find TestRunner plugin vitest" | Add `plugins: ['@stryker-mutator/vitest-runner']` explicitly to the Stryker config object. |
| Stryker + Vitest `related` warning | Set `vitest: { related: false }` in the Stryker config when using `testFiles`, and also set `testFiles` to the explicit absolute paths of the test files. |

## Repo-Specific Notes: web-ui-consolidated / web-ui

These notes apply when running in `/Users/rchen/workspace/web-ui-consolidated/web-ui`.

### Shell & pnpm

- The `web-ui/.npmrc` contains `${NPM_TOKEN}` which causes pnpm to silently fail with exit code 1 and no output in any **fresh** shell (background commands, new terminals). The foreground stateful shell works fine because it inherits the user's env.
- Always `cd` into `web-ui/` in one shell call and then run `pnpm` commands in subsequent calls — do not combine `cd && pnpm ...` in a backgrounded command.
- The `run-coverage.sh` skill script detects `pnpm` from `pnpm-lock.yaml` but must be run from within `web-ui/`, where the lockfile lives.

### Stryker

The working Stryker config for this project requires these non-default options:

```js
export default {
  testRunner: 'vitest',
  plugins: ['@stryker-mutator/vitest-runner'],   // must be explicit
  mutate: ["<relative-source-path>"],
  testFiles: ["<absolute-test-path>"],            // absolute paths work more reliably
  vitest: {
    configFile: 'vitest.config.mts',
    related: false,                               // disable Vitest's related-file graph
  },
  coverageAnalysis: 'all',                        // 'perTest' fails without sandbox node_modules
  inPlace: true,                                  // bypass sandbox; uses project node_modules
  reporters: ['json', 'clear-text'],
  jsonReporter: { fileName: 'reports/mutation/mutation.json' },
  thresholds: { high: 80, low: 60, break: null },
  logLevel: 'info',
};
```

Run it with the positional config arg (no `--configFile` flag):

```bash
npx stryker run /tmp/stryker.config.mjs
```

### CSS-in-JS Surviving Mutants

Styled-component template literals (e.g. `styled.span\`...\``) will always survive because jsdom does not evaluate CSS. These are expected and require no action.

## Additional Resources

- [OUTPUT_FORMAT.md](OUTPUT_FORMAT.md) — report template
- [scripts/resolve-files.sh](scripts/resolve-files.sh)
- [scripts/run-coverage.sh](scripts/run-coverage.sh)
- [scripts/parse-coverage.sh](scripts/parse-coverage.sh)
- [scripts/run-stryker.sh](scripts/run-stryker.sh)
- [scripts/filter-mutations.sh](scripts/filter-mutations.sh)
