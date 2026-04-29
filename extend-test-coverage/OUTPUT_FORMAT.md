# Output Report Format

Use this template to present results to the user after all phases complete.

---

## Coverage & Mutation Report

### 1. Coverage Delta

| File | Lines Before | Lines After | Branches Before | Branches After |
|------|-------------|------------|----------------|----------------|
| `src/utils/format.ts` | 62% | 94% | 50% | 88% |
| `src/hooks/useData.ts` | 45% | 91% | 40% | 85% |

### 2. Tests Generated

List each new test case added. Group by file.

**`src/utils/format.test.ts`**
- `formatCurrency` — handles negative values (line 14–15)
- `formatCurrency` — handles zero (branch 22-0)
- `formatDate` — returns fallback for invalid date (line 38)

**`src/hooks/useData.test.ts`**
- `useData` — loading state set to true on fetch start (line 22)
- `useData` — error state populated on API failure (branch 30-1)

### 3. Mutation Score

```
Mutation score: 84% ✅ Good
─────────────────────────────
Total mutants : 47
Killed        : 38
Survived      : 6
No coverage   : 2
Timeout       : 1
```

### 4. Surviving Mutants

Group by file. For each mutant, show:
- **Mutator**: the type of mutation applied
- **Location**: line:col range
- **Change**: `original → replacement`
- **Suggested fix**: what test would kill this mutant

---

**`src/utils/format.ts`**

> **Survived** | `ConditionalExpression` | Line 14:8–14:24
> ```diff
> - if (value < 0) return '-' + format(-value);
> + if (false) return '-' + format(-value);
> ```
> **Fix**: Add a test asserting `formatCurrency(-5)` returns `"-$5.00"` (the guard is never exercised with a genuine negative).

> **NoCoverage** | `ArithmeticOperator` | Line 22:15–22:20
> ```diff
> - return amount * rate;
> + return amount / rate;
> ```
> **Fix**: The surrounding function `applyTax` is never called in any test. Add a call with `rate > 1` to cover the branch.

---

**`src/hooks/useData.ts`**

> **Survived** | `StringLiteral` | Line 30:18–30:27
> ```diff
> - throw new Error('fetch failed');
> + throw new Error('');
> ```
> **Fix**: Assert that the error message equals `'fetch failed'` when the API rejects, not just that an error exists.

---

### 5. Action Items

Generated when mutation score < 80%, or when `NoCoverage` mutants exist:

- [ ] Kill surviving mutants by adding assertions listed above
- [ ] Re-run mutation testing after adding assertions: `bash ~/.cursor/skills/extend-test-coverage/scripts/run-stryker.sh "<sources>" "<tests>"`
- [ ] Aim for mutation score ≥ 80% before merging

---

### Quick Re-run Commands

```bash
# Re-run coverage only
bash ~/.cursor/skills/extend-test-coverage/scripts/run-coverage.sh "<files>"

# Re-run mutation testing only
bash ~/.cursor/skills/extend-test-coverage/scripts/run-stryker.sh "<sources>" "<tests>"
bash ~/.cursor/skills/extend-test-coverage/scripts/filter-mutations.sh reports/mutation/mutation.json
```
