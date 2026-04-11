# Memory Guide — reshade-steam

<!-- workspace-layer: L2 | trigger: on memory write or quarterly review -->
> **When to load**: Before writing to MEMORY.md, during heartbeat review, or during quarterly maintenance.

## Principles

- Use project-scoped memory for conventions discovered in this codebase.
- Use session transcripts for recent context; do not rely on long-term recall for facts that live in source files.
- Always prefer reading the source file over recalling a cached summary of it.
- When a memory conflicts with a source file, the source file wins.

## Copilot Memory Coexistence

VS Code's **built-in memory tool** (`/memories/`) provides persistent storage across sessions with three scopes. MEMORY.md exists alongside that system — complementary, not competing:

| System | Scope | What it stores | Managed by |
|--------|-------|---------------|------------|
| **Built-in** `/memories/` (user) | Global — all repos, all sessions | Personal preferences, coding style, cross-project patterns | VS Code (persistent) |
| **Built-in** `/memories/session/` | Session — current conversation only | Task-specific context, in-progress notes, working state | VS Code (cleared after conversation) |
| **Built-in** `/memories/repo/` | Repository — this workspace | Repository-scoped facts stored locally via Copilot | VS Code (persistent, repo-scoped) |
| **MEMORY.md** | Project — git-tracked, team-shared | Architectural decisions, error patterns, team conventions, gotchas | Agent + user (manual, version-controlled) |

**Priority**: MEMORY.md wins for project-specific facts. Built-in user memory wins for personal preferences.

**Key distinction**: MEMORY.md is git-tracked and team-shared. Built-in memory is personal and machine-local.

**Promotion rule**: Use `/memories/repo/` as a repo-local inbox while a task is in flight. Promote only validated, team-relevant facts into MEMORY.md once stable.

### Known Constraints

- **User memory auto-load cap**: first 200 lines of `/memories/` auto-injected; beyond 200 requires explicit read.
- **Repo memory is machine-local**: `/memories/repo/` lives under `workspaceStorage/` — not git-tracked.
- **Copilot Memory (GitHub-hosted)**: opt-in (`github.copilot.chat.copilotMemory.enabled`), 28-day auto-expiry, cross-surface. Complements this file.

When creating `/memories/repo/` entries, prefer the Copilot Memory JSON schema (`subject`, `fact`, `citations`, `reason`, `category`).

## What to Remember

- Hard-won architectural decisions.
- Cross-cutting patterns not yet in the instructions file.
- Durable repo-memory notes that need team sharing.
- User preferences observed over time (link to USER.md).

## What Not to Remember

- File contents — read them fresh.
- Test results — run them fresh.
- LOC counts — measure them fresh.

## Maintenance Protocol

- Review and prune quarterly (or when exceeding 100 rows total).
- Keep rows concise for compaction snapshots.
- Remove entries now captured in the instructions file.
- Archive pruned entries to `.github/archive/memory-pruned-YYYY-MM-DD.md` if needed.
- Move superseded/expired entries to the Archived section rather than deleting.
- Fold validated `/memories/repo/` facts into MEMORY.md; trim stale repo-local notes.
- Rules must be falsifiable — remove any entry that no longer improves agent output.

> **Provenance convention**: `file:line` for code, URL for docs, `session:{id}` for observed behaviour.
