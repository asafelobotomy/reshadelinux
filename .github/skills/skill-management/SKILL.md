---
name: skill-management
description: Discover, activate, and manage agent skills following the Skill Protocol
compatibility: ">=1.4"
---

# Skill Management

> Skill metadata: version "1.1"; license MIT; tags [skills, workflow, discovery, management]; compatibility ">=1.4"; recommended tools [codebase, editFiles, fetch].

Skills are reusable markdown-based **behavioural instructions** that teach the agent *how* to perform a specific workflow. Unlike tools (§11) which are executable scripts, skills are declarative — they shape the agent's approach rather than running code.

Skills follow the [Agent Skills](https://agentskills.io) open standard. Each skill is a `SKILL.md` file with minimal YAML frontmatter (`name`, `description`) plus a markdown body that includes a `Skill metadata` note and step-by-step workflow instructions.

Use the `description` field as the discovery surface. Do not rely on custom top-level keys such as `stacks`; VS Code does not use them when selecting a skill.

## When to use

- You encounter a task that might match an existing skill
- The user asks to list, search for, or manage skills
- You need to decide where a new skill should be stored

## Discovery and activation

Skills are loaded **on demand** — the agent reads a skill's `SKILL.md` only when the `description` field matches the current task context. Do not pre-load all skills.

```text
Task requires a workflow
 │
 ├─ 1. SCAN — check local skill directories
 │     Locations: .github/skills/, .claude/skills/, .agents/skills/
 │     Also: installed agent plugins and extension-contributed skills
 │     ├─ Match found  → READ the full SKILL.md, follow its instructions
 │     └─ No match     → ↓
 │
 ├─ 2. SEARCH (if enabled by skill search preference setting)
 │     ├─ Search official repos (anthropics/skills, github/awesome-copilot) THEN:
 │     │     community sources (GitHub search, awesome-agent-skills)
 │     │     ├─ Found → evaluate fit, quality-check, adapt, save locally
 │     │     └─ Not found → ↓
 │
 └─ 3. CREATE — author a new skill from scratch
       - Save to .github/skills/<kebab-name>/SKILL.md
```

## Scope hierarchy

| Priority | Location | Scope |
|----------|----------|-------|
| 1 (highest) | `.github/skills/<name>/SKILL.md` | Project — checked into version control |
| 2 | `.claude/skills/<name>/SKILL.md`, `.agents/skills/<name>/SKILL.md` | Project (alt) — Claude/Agent-format directories |
| 3 | `~/.copilot/skills/<name>/SKILL.md` | Personal — shared across all projects for one user |
| 4 | `~/.claude/skills/<name>/SKILL.md`, `~/.agents/skills/<name>/SKILL.md` | Personal (alt) — alternative personal paths |
| 5 | Agent plugins (`@agentPlugins`) | Plugin — installed via Extensions view (VS Code 1.110+) |
| 6 | Extension `chatSkills` contribution | Extension — VS Code extensions contributing skills via `package.json` |
| 7 | Organization-level agents | Org — published at GitHub org level for all members |

> **Custom paths**: Use the `chat.agentSkillsLocations` VS Code setting to add custom directories for skill discovery beyond the default locations. Useful for sharing skills across projects or keeping them in a central location.

## Visibility controls

Control how each skill is accessed via SKILL.md frontmatter:

| Setting | `/` menu | Auto-load | Use case |
|---------|----------|-----------|----------|
| Default (both omitted) | Yes | Yes | General-purpose skills |
| `user-invocable: false` | No | Yes | Background knowledge skills the model loads when relevant |
| `disable-model-invocation: true` | Yes | No | Skills you only want to run on demand |
| Both set | No | No | Disabled skills |

## Subagent skill use

Subagents inherit this protocol fully. A subagent may read and follow any project or personal skill. To **create** a new skill, the subagent must flag the proposal to the parent agent, which confirms before any write to `.github/skills/`.
