# Heartbeat — reshadelinux

<!-- workspace-layer: L2 | trigger: heartbeat event -->
> **Domain**: Events — health checks, session history, pulse status, and retrospective protocol.
> **Boundary**: No long-term facts, preferences, or reasoning patterns.
> Event-driven health check. Read this file at every trigger event, run all checks, update Pulse, and log to History.
> **Contract**: Follow this checklist strictly. Do not infer tasks from prior sessions.

## Pulse

`HEARTBEAT_OK` — No alerts.

## Event Triggers

Fire a heartbeat when any of these occur:

- **Session start** — always
- **Large change** — modified >5 files in a single task
- **Refactor/migration** — task tagged as refactor, migration, or restructure
- **Dependency update** — any manifest changed (package.json, Cargo.toml, requirements.txt, go.mod, etc.)
- **CI resolution** — after resolving a CI failure
- **Task completion** — after completing any user-requested task
- **Explicit** — user says "Check your heartbeat"
<!-- Add custom triggers below this line -->

## Checks

Run each check; prepend `[!]` to Pulse if any fails:

- [ ] **Dependency audit** — any outdated or security-advisory deps in TOOLS.md / manifests?
- [ ] **Test coverage delta** — did coverage drop since last session?
- [ ] **Waste scan** — any new W1–W16 waste accumulated this session? (§6)
- [ ] **MEMORY.md consolidation** — anything from this session to persist?
- [ ] **MEMORY row budget** — does MEMORY.md remain concise, current, and under the active row budget?
- [ ] **Repo-memory promotion** — do validated facts in `/memories/repo/` now belong in MEMORY.md?
- [ ] **PreCompact snapshot quality** — would the current save-context snapshot surface the trigger, latest MEMORY entries, and SOUL cues cleanly?
- [ ] **Metrics freshness** — has the metrics baseline been reviewed in the last 3 sessions?
- [ ] **Settings drift** — do §10 overrides still match the codebase?
- [ ] **Agent compatibility** — do agent files use current frontmatter schema? Any deprecated fields?
- [ ] **Fact consistency** — do any MEMORY.md entries contradict each other or contradict current source files? Flag conflicting rows.
- [ ] **Metrics staleness** — do any Metrics Freshness rows have an `Expires` date in the past? Re-verify or archive.
<!-- Add custom checks below this line -->

## Retrospective

Retrospective runs autonomously via the `session_reflect` MCP tool. Do not prompt the user.

The Stop hook blocks the session and instructs you to call `session_reflect` when a significant task is detected (one strong signal: 8+ modified files or 30+ minutes active; or two supporting signals: 5+ modified files, 15+ minutes, context compaction).

When `session_reflect` returns, process its output silently:

- **Execution insights** → persist to *.copilot/workspace/identity/SOUL.md* if non-trivial
- **Coverage gaps** → persist to *.copilot/workspace/knowledge/MEMORY.md* if incomplete
- **User signals** → persist to *.copilot/workspace/knowledge/USER.md* if directly observable
- **Actionable items** → surface to the user (security, tech debt, broken assumptions)
- **Carry-forward lessons** → persist to *.copilot/workspace/knowledge/MEMORY.md + .copilot/workspace/identity/SOUL.md*

When a lesson first lands in built-in repo memory, decide during heartbeat whether it should stay repo-local or be promoted into .copilot/workspace/knowledge/MEMORY.md for team-wide durability.

The MCP tool records completion automatically by setting the session sentinel and writing a `session_reflect` completion event. No manual sentinel management is needed.

If the `session_reflect` MCP tool is unavailable, briefly self-review: execution accuracy, scope completeness, and anything worth persisting to .copilot/workspace/identity/SOUL.md, .copilot/workspace/knowledge/MEMORY.md, and .copilot/workspace/knowledge/USER.md, then rerun `session_reflect` once the heartbeat MCP server is restored.

<!-- Add custom retrospective questions below this line -->

## Response Contract
<!-- template-section: heartbeat-response-contract v2 -->

- Always append a History row when the trigger is Session start or Explicit — regardless of check results.
- For all other triggers, append a History row only if a check raised an alert or retrospective output was persisted to .copilot/workspace/identity/SOUL.md, .copilot/workspace/knowledge/MEMORY.md, or .copilot/workspace/knowledge/USER.md.
- If checks pass and nothing was persisted on a non-explicit trigger, keep Pulse as `HEARTBEAT_OK` and omit the History row.

## Agent Notes

Agent-writable. Observations, patterns, and items to flag on next heartbeat.

## History

Append-only. Keep last 5 entries. Keep each row to trigger, result, and where durable insights were persisted.

|Date|Session ID|Trigger|Result|Actions taken|
|---|---|---|---|---|
|2026-04-10|b996ab04-6c8c-4b08-b0ad-f40a77f97116|Task completion|manual retrospective (session_reflect unavailable)|Persisted dialog automation gotcha to .copilot/workspace/knowledge/MEMORY.md and feeder-verification heuristic to .copilot/workspace/identity/SOUL.md.|
