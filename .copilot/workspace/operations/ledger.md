# Spatial Ledger — reshadelinux

<!-- workspace-layer: L2 | trigger: on spatial_status call or heartbeat -->

> Full vocabulary for the project's spatial metaphor. The compact table in §14 covers daily work;
> this file is the complete reference.

## Metaphor: village

| Term | Meaning | Maps to |
|------|---------|---------|
<!-- markdownlint-disable-next-line MD055 MD056 -->
| Village | This project workspace | Repository root |
| Town Hall | Main instructions |  |
| Building | Agent workspace |  |
| Workshop | Template layer |  |
| Trade Route | Cross-repo memory |  |
| Diary | Per-agent findings log |  |
| Ledger | Full glossary |  |

## Spaces

Spaces are the logical areas of the project. Each space maps to a directory or file group.

| Space | Path pattern | Owner agent | Purpose |
|-------|-------------|-------------|---------|
| *(populated during setup or first heartbeat)* | | | |

## Agent Homes

Each specialist agent has a home — the space it primarily operates in.

| Agent | Home space | Diary path |
|-------|-----------|------------|
| *(populated on first SubagentStart)* | | `.copilot/workspace/knowledge/diaries/{agent}.md` |

## Cross-References

| From | To | Relationship |
|------|----|-------------|
| *(populated as cross-cutting patterns emerge)* | | |

## Maintenance

- Review during heartbeat when spatial_status reports drift.
- Add new spaces when directories are created.
- Archive removed spaces rather than deleting rows.
- Keep this file under 100 lines. Move historical data to `.github/archive/`.
