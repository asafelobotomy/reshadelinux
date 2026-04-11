---
name: Onboard Commit Style
description: Interview the user to establish their commit style preferences and write .copilot/workspace/operations/commit-style.md
agent: agent
tools: [editFiles, codebase]
---

You are setting up the consumer's commit style preferences. Your goal is to populate `.copilot/workspace/operations/commit-style.md` by asking a small number of targeted questions.

**Do not write the file until you have all answers. Ask all questions together in a single message.**

## Questions to ask

1. **Format**: Do you follow Conventional Commits (`feat:`, `fix:`, `docs:` etc.) or a custom format? If custom, what does a typical commit message look like?

2. **Scope**: Do you include a scope in parentheses (e.g. `feat(api): ...`)? If yes, what style — `kebab-case`, `snake_case`, or something else? Or do you prefer to omit scopes?

3. **Body**: Is a commit body (multi-line explanation) required, optional, or never used?

4. **Sign-off**: Do you require a `Signed-off-by:` trailer (DCO)?

5. **Squash fixups**: Do you squash `fixup!` commits before pushing, or push as-is?

6. **Issue linking**: Should the Commit agent automatically add `Closes #<number>` when the branch name contains an issue number?

7. **Any other rules**: Any types you want to restrict, scope naming conventions, or anything else the Commit agent should know?

## After collecting answers

1. Write `.copilot/workspace/operations/commit-style.md` with the populated preferences.
2. Confirm to the user: "Commit style saved to `.copilot/workspace/operations/commit-style.md`. The Commit agent will apply these preferences on every invocation."
3. Offer to demonstrate by running the Commit agent on the current staged changes (if any).
