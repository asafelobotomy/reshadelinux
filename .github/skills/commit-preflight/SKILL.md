---
name: commit-preflight
description: Inspect active GitHub Actions workflows before commit or push, run matching local checks for staged or unpushed files, ask which missing tools to install via askQuestions, and fix in-scope issues so the Commit agent can proceed.
compatibility: ">=1.4"
---

# Commit Preflight

> Skill metadata: version "1.0"; license MIT; tags [commit, preflight, ci, workflow, git]; compatibility ">=1.4"; recommended tools [codebase, runCommands, editFiles, askQuestions].

Inspect the repo's active workflows before a commit or push and clear
locally reproducible failures before the Commit agent proceeds.

## When to use

- The user asks to commit or push changes
- The repo has GitHub Actions workflows or local CI scripts
- The agent needs to reduce avoidable workflow failures before a push

## When not to use

- The repo has no local checks to run
- The failing gate depends on secrets, hosted services, or other non-local inputs
- The user explicitly accepts the risk of skipping verification

## Steps

1. Determine the operation and candidate file set.
   - For commit preflight, prefer `git diff --cached --name-only`.
   - If nothing is staged and the user approved staging, use the proposed file
     list instead.
   - For push preflight, compare the branch against `origin/<branch>` and use
     the unpushed diff.
   - Stop if the file set is empty.

2. Discover active workflow gates.
   - Read `.github/workflows/*.yml`.
   - Prioritise workflows that trigger on `push` for the current branch.
   - Include `pull_request` workflows when they run the same local checks.
   - Honor `branches`, `branches-ignore`, `paths`, and `paths-ignore`.
   - When both branch and path filters exist, both must match.
   - Treat `workflow_run` workflows as downstream automation, not direct
     preflight gates, unless they expose a local planner or validation command
     that the repo already documents.

3. Build a local execution plan from the matching workflows.
   - Prefer explicit `run:` commands and repo scripts over heuristic guesses.
   - Use curated local equivalents for common wrapper actions.
   - Keep the plan ordered from cheapest checks to most expensive checks.

   | Workflow shape | Local preflight command |
   |----------------|-------------------------|
   | `run: bash tests/run-all.sh` | Run the exact command |
   | `run: bash scripts/... --check` | Run the exact command |
   | `uses: DavidAnson/markdownlint-cli2-action` | `npx markdownlint-cli2 ...` with the workflow globs |
   | `uses: raven-actions/actionlint` | `actionlint` |
   | `uses: ludeeus/action-shellcheck` | `shellcheck` with the workflow severity |
   | `run: pip install yamllint` + `yamllint ...` | Probe or install `yamllint`, then run the exact lint command |

4. Probe required dependencies before running checks.
   - Extract required commands from the local execution plan.
   - Probe each command with `command -v`.
   - If a workflow already contains an install step, reuse that install method
     as the preferred option.
   - If a dependency is missing, do not install it silently.
   - Use `askQuestions` to ask which tools, if any, the user wants installed.
   - Ask only about missing tools.

   ```yaml
   header: "Preflight Dependencies"
   question: "Some preflight checks need tools that are not installed. Which tools, if any, would you like me to install before I continue?"
   multiSelect: true
   allowFreeformInput: false
   options:
     - label: "Install yamllint"
       description: "Needed for YAML lint; the workflow already uses pip install yamllint --quiet"
       recommended: true
     - label: "Install actionlint"
       description: "Needed for workflow lint"
     - label: "Install none"
       description: "Skip the missing-tool checks and decide after the risk summary"
   ```

   > Fallback: If `askQuestions` is unavailable, present the same choices as a
   > numbered list in chat.

5. Install only what the user approved.
   - Use the workflow's install command when available.
   - Otherwise use the repo's documented package manager or the system package
     manager only after approval.
   - Re-probe commands after installation.
   - Mark failed installs as unavailable and continue to the residual-risk
     decision.

6. Run the checks.
   - Run read-only checks first.
   - Run file-scoped checks before full-suite checks.
   - Capture each command, exit status, and affected files.

7. Repair only in-scope failures.
   - If a failing check can be fixed within the candidate file set, repair it
     directly or hand off to the Code agent with the failing command, error
     output, and file scope.
   - If a fix would touch files outside scope, stop and ask whether to widen
     scope.
   - After each repair, rerun only the affected checks before moving on.

8. Decide whether the Commit agent can proceed.
   - If all applicable checks pass, return a concise pass summary.
   - If some checks were skipped because tools were unavailable or the user
     declined installation, use `askQuestions` to confirm whether to continue
     with residual risk.
   - If any required check still fails, stop the commit or push flow and report
     the exact blocker.

9. Hand back the result in one summary.
   - List executed checks.
   - List skipped checks and why.
   - List files changed by auto-fixes.
   - State whether commit or push may proceed.

## Verify

- Applicable workflow-backed checks were discovered from `.github/workflows/`
- Missing dependencies were probed before installation
- Any dependency installs were approved via `askQuestions`
- Auto-fixes stayed inside the approved scope or were explicitly re-approved
- The Commit agent received a clear pass, blocked, or residual-risk outcome
