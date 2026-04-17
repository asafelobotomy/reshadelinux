# Commit Style — reshadelinux

This file is read by the Commit agent on every invocation. Edit it to match your project's commit conventions.

## Format

```yaml
format: conventional-commits
```

Options: `conventional-commits` | `custom`

If `custom`, define the message template below in `custom-template`.

## Scope style

```yaml
scope-style: kebab-case
```

Options: `kebab-case` | `snake_case` | `PascalCase` | `omit`

## Types allowed

Leave blank to allow all Conventional Commits types. Restrict to a subset:

```yaml
types:
  - feat
  - fix
  - docs
  - style
  - refactor
  - perf
  - test
  - build
  - ci
  - chore
```

## Body

```yaml
body: optional
```

Options: `required` | `optional` | `never`

## Footer / trailer

```yaml
footer: optional
```

Add `Closes #<issue>` automatically when the branch name contains an issue number:

```yaml
auto-close-issue: true
```

## Sign-off

```yaml
sign-off: false
```

Set `true` to append `Signed-off-by: Name <email>` using the git config identity.

## Squash policy

```yaml
squash-fixups: false
```

Set `true` to run `git rebase -i --autosquash` before pushing when fixup commits are present.

## Custom template

Only used when `format: custom`. Use `{type}`, `{scope}`, `{subject}`, `{body}` tokens.

```yaml
custom-template: ""
```

## Notes

<!-- Add any project-specific commit notes here. -->
