---
name: Configuration Files
applyTo: "**/*.config.*,**/.*rc,**/.*rc.json,**/.*rc.yml,**/.*rc.js,**/.*rc.ts"
description: "Conventions for configuration and RC files — secrets management, minimal config, and startup validation"
---

# Configuration File Instructions

- Never hardcode secrets, tokens, or credentials in config files — use environment variables.
- Prefer explicit configuration over convention-based defaults when the default is surprising.
- Keep config files minimal — document non-obvious settings with inline comments.
- When adding a new config key, check whether an existing key already covers the intent.
- Validate config at application startup, not at point of use.

## Resolve Config in a Predictable Order

Use one resolution order. Later layers override earlier ones.

1. Hard-coded defaults in the script or app.
2. User-level config such as `~/.copilot/hooks` or `~/.claude/settings.json`.
3. Repository workspace config such as `.github/hooks/*.json` or repo-scoped config files.
4. Local overrides such as `.claude/settings.local.json`. Keep them gitignored and never commit them.
5. Environment variables for secrets and deploy-time values.

- Credentials must come from environment variables, never from committed config files.
- Do not group config into named environments such as `dev`, `staging`, or `prod`.
- Use orthogonal per-value variables instead. Named groups do not scale cleanly.
- Document any required local override in setup docs because CI cannot see it.
