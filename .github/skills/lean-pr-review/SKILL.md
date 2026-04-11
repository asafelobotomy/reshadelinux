---
name: lean-pr-review
description: Review a pull request using Lean waste categories and structured severity ratings
compatibility: ">=1.4"
---

# Lean PR Review

> Skill metadata: version "1.1"; license MIT; tags [review, pull-request, lean, kaizen, code-review]; compatibility ">=1.4"; recommended tools [codebase, githubRepo].

Perform a structured pull request review using §5 Review Mode conventions and §6 waste categories.

## When to use

- The user asks to "review this PR", "review these changes", or "check my diff"
- The Review agent hands off a PR-scoped review task
- A pull request needs a quality gate before merge

## When NOT to use

- The user wants a full architectural review (use Review Mode directly with the full codebase)
- The changes are a single-line typo fix (overkill — just approve)

## Steps

1. **Get the diff** — Read the PR diff or the set of changed files. If working locally, use `git diff main...HEAD` or the equivalent for the target branch.

2. **Scan each changed file** — For every file in the diff, read the full file (not just the diff hunk) to understand context.

3. **Classify each finding** — For every issue found, record:

   ```text
   [severity] | [file:line] | [waste category] | [description]
   ```

   Severity levels:
   - `critical` — blocks merge; security flaw, data loss risk, or broken functionality
   - `major` — should fix before merge; logic error, missing test, or significant smell
   - `minor` — nice to fix; style issue, naming, minor inefficiency
   - `advisory` — informational; suggestion for future improvement

   Waste categories (§6) — full list W1–W16; most common in PR review:

   | Code | Name | Typical PR signal |
   |------|------|------------------|
   | W1 | Overproduction | Dead code, unused exports, features not yet needed |
   | W2 | Waiting | Blocking sync calls, missing timeouts |
   | W3 | Transport | Unnecessary data copying, prop drilling 3+ levels |
   | W4 | Over-processing | Abstraction for its own sake, premature generalisation |
   | W5 | Inventory | Large WIP; changes that could be split into smaller PRs |
   | W6 | Motion | Logic scattered across many files without justification |
   | W7 | Defects | Bugs, type errors, missing error handling, test failures |
   | W8 | Unused talent | Missing tests, missing automation, repetitive manual patterns |
   | W11 | Hallucination rework | Phantom API usage, methods that don't exist, incorrect assumptions |
   | W14 | Model-task mismatch | Overly complex solution to a trivial problem |

   For W9–W10, W12–W13, W15–W16 definitions, see §6 of `.github/copilot-instructions.md`.

4. **Check test coverage** — Verify that new or changed behaviour has corresponding tests. Flag untested paths as `major | W7 Defects`.

5. **Check for baseline breaches** — Compare against §2 baselines:
   - File LOC limits (warn / hard)
   - Dependency budget (if deps were added)
   - Type errors (must be zero)

6. **Produce the report** — Format as:

   ```markdown
   ## PR Review — <PR title or branch name>

   ### Summary
   <1–2 sentence overview of the changes and their quality>

   ### Findings (<N> total: <critical> critical, <major> major, <minor> minor, <advisory> advisory)

   #### Critical
   - [critical] | [file:line] | [W7] | <description>

   #### Major
   - [major] | [file:line] | [W4] | <description>

   #### Minor
   - [minor] | [file:line] | [W1] | <description>

   #### Advisory
   - [advisory] | [file:line] | [W8] | <description>

   ### Verdict
   <APPROVE / REQUEST CHANGES / COMMENT>
   ```

7. **Wait** — Do not apply fixes. Present the report and wait for the user to decide what to address.

## Verify

- [ ] Every finding has all four fields: severity, file:line, waste category, description
- [ ] Critical findings are genuinely blocking (not inflated)
- [ ] Test coverage was checked for all new behaviour
- [ ] Baseline breaches are flagged
- [ ] Report ends with a clear verdict
