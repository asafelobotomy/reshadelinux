# Agent Diaries

Per-agent findings logs. Each file is named `{agent-name}.md` and capped at 30 lines.

- **Layer**: L2 (loaded on demand via SubagentStart hook)
- **Write trigger**: Agent discovers a durable insight worth sharing across sessions
- **Dedup**: Grep for the finding text before writing — skip if already present
- **Archival**: When a diary exceeds 30 lines, move older entries to `.github/archive/`
