---
name: optimizely-feature-flags
description: Inspect and query Optimizely feature flag datafiles. Fetches a public CDN datafile by SDK key, checks if an endpoint requires auth, and parses flags by rollout state (e.g. ON/OFF for everyone, per environment). Use when the user mentions Optimizely, feature flags, a datafile URL (cdn.optimizely.com), or wants to audit which flags are enabled/disabled by default in production.
---

# Optimizely Feature Flags

## Datafile URL format

```
https://cdn.optimizely.com/datafiles/<SDK_KEY>.json
```

The endpoint is **publicly accessible** — no authentication required.

## Datafile structure

Key top-level fields:

| Field | Description |
|-------|-------------|
| `environmentKey` | e.g. `production`, `staging` |
| `sdkKey` | Matches the URL path segment |
| `featureFlags` | Array of flags (`id`, `key`, `rolloutId`, `experimentIds`) |
| `rollouts` | Rollout rules; each has an `experiments` array (the targeting rules) |

## How rollout rules work

Each rollout contains an ordered list of `experiments` (targeting rules):
- Non-last rules target specific audiences via `audienceConditions`
- The **last rule** with `audienceConditions: []` is the **"Everyone Else"** fallback
- `trafficAllocation[].endOfRange` of `10000` = 100% of that audience
- The matched variation's `featureEnabled` field is the on/off state

## Parsing fully-ON flags (all rules + everyone else)

A flag is **fully ON** when every rule in its rollout — including all audience-targeted rules and the "Everyone Else" fallback — has `featureEnabled: true` at 100% traffic. This is the only definition of "on" that matters.

```python
import json

with open('datafile.json') as f:
    data = json.load(f)

print('Environment:', data.get('environmentKey'))

rollouts_by_id = {r['id']: r for r in data['rollouts']}

def rule_is_on(exp):
    traffic = exp.get('trafficAllocation', [])
    if not traffic:
        return False
    top = max(traffic, key=lambda t: t['endOfRange'])
    if top['endOfRange'] != 10000:
        return False
    variations = {v['id']: v for v in exp.get('variations', [])}
    var = variations.get(top['entityId'])
    return var.get('featureEnabled', False) if var else False

fully_on = []
for flag in data['featureFlags']:
    rollout = rollouts_by_id.get(flag.get('rolloutId'))
    if not rollout:
        continue
    exps = rollout.get('experiments', [])
    if not exps:
        continue
    # Last rule must be the Everyone Else fallback (empty audienceConditions)
    if exps[-1].get('audienceConditions') != []:
        continue
    # Every rule (audience-targeted + Everyone Else) must be ON at 100%
    if all(rule_is_on(exp) for exp in exps):
        fully_on.append(flag['key'])

fully_on.sort()
print(f'Fully ON flags: {len(fully_on)}')
for key in fully_on:
    print(key)
```

## Fetching the datafile directly

Use `WebFetch` with `https://cdn.optimizely.com/datafiles/<SDK_KEY>.json`. The response is saved to a temp file — load it with the python snippet above via `Shell`.

## Finding fully-ON flags referenced in the repo

After obtaining the `fully_on` list, search the codebase for each key using `Grep` with an alternation pattern. Flag keys are passed as plain strings to `featureName:` props/params — no central registry exists.

```python
# Generate the alternation pattern from fully_on list
print('|'.join(fully_on))
```

Then use `Grep` with that pattern across `*.{ts,tsx}` files:

```
pattern: <key1>|<key2>|...
path: web-ui/src
glob: *.{ts,tsx}
output_mode: files_with_matches   # first pass: which files
output_mode: content              # second pass: exact lines
```

**Interpreting results — watch for false positives:**
- Match must appear as a quoted string (e.g. `featureName: 'deploy_pipeline'`), not as a field name or analytics event
- Flag keys that look like common words (e.g. `members_count`, `job_timing`) may match unrelated code
- Matches in `*.test.*` / `*.mock.*` files are not production references

## Checking for existing PRs

After collecting `flag_files`, check whether each flag already has an open PR before presenting results or launching agents. The `feature-flag-removal` skill names branches `cleanup/remove-<flag_name_with_hyphens>-feature-flag`.

```python
import subprocess, json

def branch_for_flag(flag_key):
    return f"cleanup/remove-{flag_key.replace('_', '-')}-feature-flag"

def has_open_pr(flag_key):
    branch = branch_for_flag(flag_key)
    result = subprocess.run(
        ["gh", "pr", "list", "--head", branch, "--state", "open", "--json", "number,url,title"],
        capture_output=True, text=True
    )
    prs = json.loads(result.stdout) if result.returncode == 0 else []
    return prs[0] if prs else None

# Build a dict: flag_key -> pr info (or None)
existing_prs = {flag: has_open_pr(flag) for flag in flag_files}
```

Use this map to drive Mode 1 display and Mode 2 filtering below.

---

## Mode detection

Before outputting results, detect the user's intent from their message:

| Intent signals | Mode |
|----------------|------|
| "audit", "show me", "which flags", "list", "what's fully on", no explicit action | **Mode 1: Audit** — output the table with copy links |
| "remove all", "clean up all", "remove them", "run cleanup", "do it", "fix them all" | **Mode 2: Bulk Cleanup** — launch subagents |
| Ambiguous | Default to **Mode 1**, then ask at the end: *"Want me to launch cleanup agents for all of these?"* |

---

## Mode 1: Audit — results table

After filtering confirmed matches, output a markdown table. Each row gets a clipboard-copy link so the cleanup prompt can be pasted directly into a new agent session.

Use this Python snippet to generate the table after collecting `flag_files` (a dict of `flag_key -> [file_path, ...]`) and `existing_prs` (from the PR-check step above):

```python
from urllib.parse import quote

def make_prompt(flag_key):
    return (
        f"Remove the '{flag_key}' feature flag from the codebase. "
        f"It is fully ON in production for all users (100% rollout, all rules). "
        f"Use the feature-flag-removal skill if available: inline the enabled code path "
        f"and delete all gating logic and the useFeatureFlag call."
    )

def make_copy_link(flag_key):
    prompt = make_prompt(flag_key)
    # javascript: URI that copies the prompt text to the clipboard when clicked
    js = f"navigator.clipboard.writeText({repr(prompt)})"
    return f"javascript:{quote(js)}"

print("| Flag | Files | Status | Action |")
print("|------|-------|--------|--------|")
for flag, files in sorted(flag_files.items()):
    file_list = "<br>".join(f"`{f}`" for f in files)
    pr = existing_prs.get(flag)
    if pr:
        status = f"[PR #{pr['number']} open]({pr['url']})"
        action = "_(PR already open)_"
    else:
        status = "ready"
        link = make_copy_link(flag)
        action = f"[Copy prompt]({link})"
    print(f"| `{flag}` | {file_list} | {status} | {action} |")
```

Example output row:
| Flag | Files | Status | Action |
|------|-------|--------|--------|
| `deploy_pipeline` | `project-home/components/environments/EnvironmentList.tsx`<br>`deploys/component/releases/ReleaseActions/index.tsx` | ready | [Copy prompt](javascript:navigator.clipboard.writeText("Remove%20the%20'deploy_pipeline'%20feature%20flag%20from%20the%20codebase.%20It%20is%20fully%20ON%20in%20production%20for%20all%20users%20(100%25%20rollout%2C%20all%20rules).%20Use%20the%20feature-flag-removal%20skill%20if%20available%3A%20inline%20the%20enabled%20code%20path%20and%20delete%20all%20gating%20logic%20and%20the%20useFeatureFlag%20call.")) |
| `some_other_flag` | `src/components/Foo.tsx` | [PR #1234 open](https://github.com/...) | _(PR already open)_ |

Click **Copy prompt** to copy the pre-filled cleanup instruction to your clipboard, then paste it into a new Cursor agent chat.

---

## Mode 2: Bulk cleanup — launching subagents

When the user wants to remove all confirmed flags, use the `Task` tool to launch **one subagent per flag**. Issue all `Task` calls in a **single response** so they run in parallel.

**Skip any flag that already has an open PR** (from `existing_prs`). Before launching agents, report which flags were skipped:
> "Skipping N flag(s) with PRs already open: `flag_a`, `flag_b`. Launching agents for the remaining M."

- `subagent_type`: `"best-of-n-runner"` — each flag gets an isolated git worktree and branch
- `run_in_background`: `true` — parallel execution, non-blocking

**Task description:** `"Remove <flag_key> feature flag"`

**Prompt template** (fill in `FLAG_KEY` and `FILE_LIST` for each flag):

```
You are removing the '<FLAG_KEY>' feature flag from the web-ui-consolidated codebase.

This flag is fully ON in production for all users (100% rollout, all rules enabled).
Treat the enabled code path as the new permanent behavior.

Known source files containing this flag:
<FILE_LIST — one path per line>

Steps:
1. Read and follow the skill at: /Users/rchen/.cursor/skills/feature-flag-removal/SKILL.md
2. Use '<FLAG_KEY>' as the featureName input.
3. The skill will guide you through: creating a branch, removing the flag from all files,
   cleaning up tests, running typecheck/lint, and opening a PR.

Proceed through all steps autonomously without asking for confirmation.
```

Use this Python snippet to print the per-flag prompts for copy/paste into `Task` calls (already filtered to exclude flags with open PRs):

```python
SKILL_PATH = "/Users/rchen/.cursor/skills/feature-flag-removal/SKILL.md"

# Exclude flags that already have an open PR
flags_to_run = {flag: files for flag, files in flag_files.items() if not existing_prs.get(flag)}
skipped = [flag for flag in flag_files if existing_prs.get(flag)]

if skipped:
    print(f"Skipping {len(skipped)} flag(s) with PRs already open: {', '.join(sorted(skipped))}")

for flag, files in sorted(flags_to_run.items()):
    file_list = "\n".join(f"  - {f}" for f in files)
    print(f"""
--- Task: Remove '{flag}' ---
subagent_type: best-of-n-runner
run_in_background: true
description: "Remove {flag} feature flag"
prompt:
  You are removing the '{flag}' feature flag from the web-ui-consolidated codebase.

  This flag is fully ON in production for all users (100% rollout, all rules enabled).
  Treat the enabled code path as the new permanent behavior.

  Known source files containing this flag:
{file_list}

  Steps:
  1. Read and follow the skill at: {SKILL_PATH}
  2. Use '{flag}' as the featureName input.
  3. The skill will guide you through: creating a branch, removing the flag from all files,
     cleaning up tests, running typecheck/lint, and opening a PR.

  Proceed through all steps autonomously without asking for confirmation.
""")
```

After all `Task` calls are issued, tell the user:
> "Launched {N} cleanup agents in parallel — one per flag. Each will create its own branch and open a PR. You can monitor progress in the background terminals."

If any flags were skipped, append:
> "Skipped {skipped_count} flag(s) with PRs already open: `flag_a`, `flag_b`."

## Notes

- `experimentIds` on a flag are A/B experiments; flags can be gated by both rollouts AND experiments
- Flags with no `rolloutId` have no rollout configured (neither on nor off by default)
- Partial rollouts: `endOfRange < 10000` means only a percentage gets the feature — not "everyone"
- Flags absent from the repo are typically owned by backend/infra services (`notifications-*`, `providers-service-*`, `stripe-*`, etc.)
