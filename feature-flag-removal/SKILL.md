---
name: generic-feature-flag-removal
description: Removes a feature flag from any codebase and simplifies the logic gated behind it, assuming the flag is permanently enabled (treated as always true). Works with any flag system — React hooks, LaunchDarkly, Optimizely, environment variables, config objects, custom utilities, etc. Use when a feature flag has been fully rolled out and needs cleanup, or when the user provides a flag name and asks to remove it.
---

# Generic Feature Flag Removal

Removes a feature flag from any codebase, treating it as **permanently ON** (enabled branch becomes the new permanent behavior).

> **Subagent use:** When invoked as a subagent, the flag name and any known file list are provided in the prompt — skip confirmation steps and proceed autonomously.

## Input

The caller provides a flag name/key, e.g. `my_feature`, `MY_FEATURE`, `myFeature`, `enable-new-checkout`.

---

## Step 0 — Branch from main

```bash
git fetch origin
git checkout main
git pull origin main
git checkout -b cleanup/remove-<flag-name>-feature-flag
```

Use hyphens in the branch name, e.g. `cleanup/remove-my-feature-feature-flag`.

---

## Step 1 — Discover usages

Search broadly using the flag name (try multiple casing variants):

```bash
rg "<FLAG_NAME>" --files-with-matches
rg "<FLAG_NAME>" --glob '*.test.*' --files-with-matches  # unit tests
rg "<FLAG_NAME>" --glob '*.spec.*' --files-with-matches  # e2e / integration tests
```

Also search for common flag registration patterns (flag definition files, flag config, feature flag lists):

```bash
rg "<FLAG_NAME>" --files-with-matches -g '*.json' -g '*.yaml' -g '*.yml' -g '*.ts' -g '*.js'
```

Categorize every match as one of:
- **Source file** — runtime code that reads the flag
- **Test file** — mocks or assertions about the flag state
- **Config/registry file** — where the flag is declared or registered

---

## Step 2 — Identify the flag pattern

Before editing, read a representative source file to identify the exact lookup pattern. Common patterns:

| Pattern type | Example |
|---|---|
| React/hook | `const { isEnabled } = useFlag('my_feature')` |
| Function call | `const enabled = featureFlags.isEnabled('my_feature')` |
| SDK client | `ldClient.variation('my-feature', false)` |
| Environment variable | `process.env.FEATURE_MY_FEATURE === 'true'` |
| Config object | `config.features.myFeature` |
| Boolean prop | `<Component featureEnabled={...} />` |

Note the **alias** (variable name) used to hold the flag value — you'll need this in Step 3.

---

## Step 3 — Simplify source files

For each source file, read it, then apply the following substitution rules treating the flag as `true`:

| Pattern | Replace with |
|---|---|
| `alias && <Foo />` | `<Foo />` |
| `alias && condition && <Foo />` | `{condition && <Foo />}` |
| `!alias && <Foo />` | *(delete — dead code)* |
| `if (alias) { ... }` | keep body, remove `if` wrapper |
| `if (!alias) { ... }` | delete entire block |
| `alias ? A : B` | `A` |
| `!alias ? A : B` | `B` |
| `alias \|\| fallback` | `alias` (remove fallback) |
| `condition && alias` | `condition` |
| `condition && !alias` | `false` / delete branch |

After substitutions:

1. **Remove the flag lookup line** — the entire `const alias = ...` / hook call / SDK call.
2. **Remove now-unused imports** — the flag utility/hook import if no other flag uses it in this file.
3. **Remove now-unused variables** — any variable that was only needed to build the flag call (e.g. user ID passed solely as a flag attribute).

---

## Step 4 — Clean up test files

### Unit tests
- Remove `mockReturnValue`, `jest.mock`, `vi.mock`, or `stub` calls that set this flag.
- Delete test cases whose **sole purpose** is asserting behavior when the flag is disabled (`"when flag is off"`, `"when flag is disabled"`, etc.).
- Collapse `"when flag is on"` describe blocks — move their tests to the top level and remove the describe wrapper.

### Integration / E2E tests
- Remove `beforeEach` / `beforeAll` blocks that mock or enable this flag.
- Delete spec files or describe blocks whose **only purpose** was testing the flag-gated behavior as opt-in.

---

## Step 5 — Clean up config / registry files

Examples of what to look for (project-specific):
- Flag definition files (Optimizely datafile, LaunchDarkly flag config, custom JSON registry)
- Seed data or fixture files that declare the flag
- Middleware or initialization code that registers the flag

Remove the flag's entry from these files.

---

## Step 6 — Verify

Run the project's standard lint and type-check commands. These vary by project — check `package.json` scripts or the project's contributing guide. Common examples:

```bash
# JS/TS projects
npm run lint && npm run typecheck

# Python projects
ruff check . && mypy .

# Go projects
go vet ./...
```

Fix any errors before proceeding.

---

## Step 7 — Create a PR

1. Gather diff context: `git diff origin/main`
2. Check if the project has a PR template (`.github/PULL_REQUEST_TEMPLATE.md` or similar).
3. **Title:** Imperative, e.g. `cleanup: remove my_feature feature flag`
4. **Body:** Summarize which files changed, why, and confirm the previously-flagged behavior is now always active. Fill in all PR template sections.
5. Push branch and open a non-draft PR targeting `main`.

---

## Decision guide for ambiguous cases

**Flag has both an enabled and disabled path that are both valuable?**
→ Stop. This flag may not be fully rolled out yet. Confirm with the caller.

**Flag found in a shared config consumed by multiple services?**
→ Search across all services before editing the shared config.

**Flag controlled by an environment variable (not a flag service)?**
→ Remove the env var check and its default value. Update `.env.example` / docs if present.

**Flag value is not a simple boolean (e.g. a string variant)?**
→ Identify the target variant from the caller, then treat it as the hardcoded value everywhere.
