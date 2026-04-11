---
name: conventional-commit
description: Write a commit message following the Conventional Commits specification with scope and body
compatibility: ">=1.4"
---

# Conventional Commit

> Skill metadata: version "1.1"; license MIT; tags [git, commit, conventional-commits, changelog, versioning]; compatibility ">=1.4"; recommended tools [codebase, runCommands].

Write a well-structured commit message following the [Conventional Commits](https://www.conventionalcommits.org/) specification.

## When to use

- The user asks to "write a commit message" or "commit these changes"
- Changes are staged and ready to commit
- The user wants consistent, parseable commit history

## When NOT to use

- The user has their own commit message format documented in §10 of their project's Copilot instructions
- The project uses a different commit convention (check §4 and §10 of the project's Copilot instructions first)

## Steps

1. **Read the staged changes** — Run `git diff --cached --stat` to see which files changed, then `git diff --cached` for the full diff.

2. **Determine the type** — Choose the most appropriate type:

   | Type | When to use |
   |------|------------|
   | `feat` | A new feature or capability |
   | `fix` | A bug fix |
   | `docs` | Documentation-only changes |
   | `style` | Formatting, whitespace, semicolons — no logic change |
   | `refactor` | Code change that neither fixes a bug nor adds a feature |
   | `perf` | Performance improvement |
   | `test` | Adding or correcting tests |
   | `build` | Build system or external dependency changes |
   | `ci` | CI configuration changes |
   | `chore` | Maintenance tasks that don't modify src or test files |

3. **Determine the scope** — Identify the primary area affected (e.g., `auth`, `api`, `ci`, `docs`). Use the directory name or module name. Omit scope if the change spans many areas.

4. **Write the subject line** — Format: `<type>(<scope>): <imperative summary>`
   - Use imperative mood ("add", not "added" or "adds")
   - Lowercase first letter after the colon
   - No period at the end
   - Maximum 72 characters

5. **Write the body** (if the change is non-trivial):
   - Blank line after the subject
   - Explain *what* changed and *why* (not *how* — the diff shows how)
   - Wrap at 72 characters
   - Reference issue numbers if applicable: `Fixes #123`, `Closes #456`

6. **Add breaking change footer** (if applicable):
   - Add `!` after the type/scope: `feat(api)!: remove v1 endpoints`
   - Add footer: `BREAKING CHANGE: <description of what breaks and migration path>`

7. **Present the message** — Show the complete commit message for user review:

   ```text
   <type>(<scope>): <subject>

   <body>

   <footer>
   ```

8. **Wait for approval** — Present the message and wait. Do not run `git commit` until the user approves or modifies the message.

9. **Execute** — Once the user approves, run:

   ```bash
   git commit -m "<subject>" -m "<body>"
   ```

   For multi-line messages with footers, use a heredoc or a temporary file to avoid shell escaping issues:

   ```bash
   git commit -F - <<'EOF'
   <type>(<scope>): <subject>

   <body>

   <footer>
   EOF
   ```

   Confirm the commit was created: `git log --oneline -1`

## Co-author attribution

VS Code 1.110+ supports `git.addAICoAuthor` (enabled by default), which automatically appends a `Co-authored-by: GitHub Copilot` trailer to commits made with AI assistance. If this setting is enabled, the trailer is added automatically — you do not need to include it manually in the commit message.

To check or change the setting: search for `git.addAICoAuthor` in VS Code Settings.

## Verify

- [ ] Type is one of the standard Conventional Commits types
- [ ] Subject line is imperative mood, ≤ 72 characters, no trailing period
- [ ] Body explains what and why (if present)
- [ ] Breaking changes have both `!` marker and `BREAKING CHANGE:` footer
- [ ] The message accurately describes all staged changes
- [ ] `git log --oneline -1` confirms the commit was created
