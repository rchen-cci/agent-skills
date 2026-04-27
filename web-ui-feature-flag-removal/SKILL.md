---
name: feature-flag-removal
description: Removes a feature flag from the codebase and simplifies the logic that was gated behind it, assuming the flag is permanently enabled. Use when a feature flag has been fully rolled out and needs to be cleaned up, or when the user provides a feature flag name and asks to remove it.
---

# Feature Flag Removal

Removes a `useFeatureFlag` flag from this repo, assuming the flag is **permanently ON** (i.e. treat the enabled branch as the new permanent behavior).

> **Subagent use:** This skill is designed to be called directly by a user *or* invoked autonomously by a parent agent (e.g. from the `optimizely-feature-flags` skill in bulk-cleanup mode). When running as a subagent, the flag key and affected file list are provided in the prompt — skip any confirmation steps and proceed through all steps autonomously.

## Input

The caller provides a `featureName` string, e.g. `archive_component`.

## Step 0 — Create a branch from main

Before touching any files, create and check out a fresh branch from the latest `main`:

```bash
git fetch origin
git checkout main
git pull origin main
git checkout -b cleanup/remove-${FLAG}-feature-flag
```

Use the branch naming convention `cleanup/remove-<flag_name>-feature-flag` (replace underscores in the flag name with hyphens).

## Step 1 — Discover all usages

Run two searches (both are required):

```bash
# Source usages
rg "featureName: '${FLAG}'" web-ui/src --files-with-matches

# E2E test helper registrations
rg "${FLAG}" web-ui/test/e2e --files-with-matches

# Unit test mocks
rg "${FLAG}" web-ui/src --glob '*.test.*' --files-with-matches
```

## Step 2 — Remove from each source file

For every source file that matched, do the following. Read the file first.

### 2a. Find the hook call and its alias

```ts
const { isFeatureEnabled: isArchiveComponentFFEnabled } = useFeatureFlag({
  featureName: 'archive_component',
  attributes: { ... },
});
```

Note the alias (`isArchiveComponentFFEnabled` in the example above).

### 2b. Simplify every usage of the alias (assume flag = `true`)

| Pattern | Replace with |
|---|---|
| `{alias && <Foo />}` | `<Foo />` |
| `{alias && condition && <Foo />}` | `{condition && <Foo />}` |
| `{!alias && <Foo />}` | *(delete — dead code when flag=true)* |
| `if (alias) { ... }` | keep body, remove `if` wrapper |
| `alias ? A : B` | `A` |
| `!alias ? A : B` | `B` |
| `someVar && !alias` | `false` / delete entire branch |

### 2c. Remove the hook call

Delete the entire `const { ... } = useFeatureFlag({ featureName: '${FLAG}', ... });` line.

### 2d. Clean up now-unused imports and hooks

- If `useFeatureFlag` is no longer called anywhere in the file, remove it from the `import { useFeatureFlag } from '~/libs/feature-flags'` line (or remove the import entirely if it was the only named export used).
- If `useMeContext` / `me` / `orgId` were **only** used for the `attributes` argument of this flag, remove those hook calls and their imports too.
- If any other variable becomes unused after the removals, remove it.

## Step 3 — Clean up E2E test helpers

In `web-ui/test/e2e/tests/deploys/helpers/feature-flags.ts` (or similar):

- Remove the entry for `${FLAG}` from the `featureFlags` array in `mockImplementation`.
- If the array becomes empty, consider removing the whole helper or the entire `featureFlags` key from the mock body.
- Remove `beforeEach` blocks in E2E specs that only mock `${FLAG}`.
- Delete entire spec files or `test.describe` blocks whose **sole purpose** was gating behavior behind `${FLAG}` (e.g. "renders only when flag is enabled" tests) — the behavior is now always on.

## Step 4 — Clean up unit test mocks

In unit test files (`*.test.tsx`):

- Remove `useFeatureFlag.mockReturnValue({ isFeatureEnabled: true/false })` calls that reference this flag.
- Remove test cases whose description says "when flag is enabled / disabled" — collapse to a single baseline test.
- If the whole file only tested flag-gated behavior and now collapses to nothing meaningful, note this to the user.

## Step 5 — Verify

```bash
cd web-ui
pnpm typecheck
pnpm lint:fix && pnpm lint
```

Fix any remaining errors before proceeding.

## Step 6 — Create a PR

1. **Pre-push:** Run `pnpm fix:all` from `web-ui/` and fix any failures.
2. **Gather context:** diff against `origin/main`, read `.github/PULL_REQUEST_TEMPLATE.md`.
3. **Title:** Imperative, e.g. `cleanup: remove archive_component feature flag`.
4. **Body:** Fill every section of the PR template (no omissions).
   - Summarize which files were changed and why.
   - Testing steps: `pnpm start` → navigate to the affected page → confirm the previously-flagged behavior is always on.
5. **Push & create:** Push the branch and open a non-draft PR targeting `main`.

---

## Real example: `archive_component`

**Files touched:**

| File | What changed |
|---|---|
| `src/deploys/component/components/ComponentGrid/index.tsx` | Removed `isArchiveComponentFFEnabled` hook call; unwrapped `{isArchiveComponentFFEnabled && (<> {isArchived ? <RestoreComponentButton> : <ArchiveComponentButton>} </>)}` → render the buttons unconditionally |
| `src/pages/deploys/[vcsType]/[orgName]/components/[componentId]/index.tsx` | Same — removed hook call, kept `{!isArchived && <ArchiveComponentButton>}` and `<RestoreComponentButton>` unconditionally in the archived state block, removed `isArchiveComponentFFEnabled &&` guards |
| `test/e2e/tests/deploys/helpers/feature-flags.ts` | Removed `archive_component` entry from `featureFlags` array |
| `test/e2e/tests/deploys/commands/archiveComponent.spec.ts` | Removed `featureFlags.mockImplementation(...)` `beforeEach` that enabled the flag |

**Before (ComponentGrid):**
```tsx
const { isFeatureEnabled: isArchiveComponentFFEnabled } = useFeatureFlag({
  featureName: 'archive_component',
  attributes: { userAnalyticsId: me?.id, organizationId: orgId },
});
// ...
<GridColumn>
  {isArchiveComponentFFEnabled && (
    <>
      {isArchived ? <RestoreComponentButton ... /> : <ArchiveComponentButton ... />}
    </>
  )}
</GridColumn>
```

**After (ComponentGrid):**
```tsx
<GridColumn>
  {isArchived ? <RestoreComponentButton ... /> : <ArchiveComponentButton ... />}
</GridColumn>
```
