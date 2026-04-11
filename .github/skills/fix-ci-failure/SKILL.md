---
name: fix-ci-failure
description: Diagnose and fix a failing CI pipeline or GitHub Actions workflow
compatibility: ">=1.4"
---

# Fix CI Failure

> Skill metadata: version "1.0"; license MIT; tags [ci, github-actions, debugging, pipeline, workflow]; compatibility ">=1.4"; recommended tools [codebase, editFiles, runCommands].

Systematically diagnose and resolve a failing CI pipeline or GitHub Actions workflow.

## When to use

- A CI job is red and the user asks to fix it
- A pull request is blocked by a failing check
- The user says "CI is failing", "fix the build", or "why is the pipeline red?"

## When NOT to use

- The failure is in a third-party service (e.g., npm registry down) — report and wait
- The user wants to redesign the CI pipeline from scratch — use Planning Mode instead

## Steps

1. **Identify the failing job** — Read the workflow file (`.github/workflows/*.yml`) and find which job and step failed. If the user has pasted log output, start there instead.

2. **Categorise the failure**:

   | Category | Signals | Typical fix |
   |----------|---------|-------------|
   | Lint / format | ESLint, Prettier, markdownlint, Ruff errors | Fix source files to pass linter rules |
   | Type check | TypeScript, mypy, cargo check errors | Fix type errors in source |
   | Test failure | Jest, pytest, cargo test, go test failures | Fix failing test or the code it tests |
   | Build failure | Compilation error, missing dependency | Fix build config or install missing dep |
   | Structural | Missing file, bad symlink, wrong path | Create/move the missing file |
   | Permission | Token expired, secret missing, scope error | Report to user — cannot fix secrets |
   | Timeout | Job exceeded time limit | Optimise or split the job |

3. **Read the relevant source** — Open the files implicated by the error. Read enough context to understand the root cause (minimum 20 lines around each error location).

4. **Fix the root cause** — Make the minimum change needed to pass the check. Do not refactor unrelated code in the same commit.

5. **Verify locally** — Run the equivalent check locally:
   - For lint: run the linter command from the workflow
   - For tests: run the repository's main test command (for example, `npm test`, `pytest`, or `bash tests/run-all.sh`)
   - For structure: verify the file exists with `ls -la`

6. **Check for cascade** — After fixing, scan for secondary failures that the primary fix might have introduced. Run the full three-check ritual if available.

7. **Summarise** — Report:
   - What failed (job name, step, error message)
   - Root cause (one sentence)
   - What was changed (files + LOC delta)
   - Verification result (local check passed / still pending)

## Verify

- [ ] The failing check would now pass with the changes made
- [ ] No unrelated changes were introduced
- [ ] The fix addresses the root cause, not just the symptom
- [ ] Summary includes all four items listed in step 7
