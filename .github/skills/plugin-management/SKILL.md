---
name: plugin-management
description: Discover, evaluate, install, test, and manage agent plugins for VS Code Copilot
compatibility: ">=3.2"
---

# Plugin Management

> Skill metadata: version "1.1"; license MIT; tags [plugins, agents, extensions, discovery, management]; compatibility ">=3.2"; recommended tools [codebase, runCommands, editFiles].

Agent plugins (VS Code 1.110+, Preview) are installable packages that bundle agents, skills, hooks, MCP servers, and slash commands. This skill covers discovering, evaluating, installing, testing, and managing plugins alongside the template's own customization files.

## When to use

- The user asks to find, list, install, or manage agent plugins
- A task would benefit from a plugin-provided agent or skill
- You need to check for conflicts between plugin-contributed and workspace-level agents or skills
- The user wants to test the template as a local plugin

## What plugins provide

A single plugin can bundle any combination of:

| Type | Description |
|------|-------------|
| Slash commands | Additional `/` commands in chat |
| Skills | Agent skills with instructions, scripts, and resources |
| Agents | Custom agents with specialized personas and tool configurations |
| Hooks | Shell commands at agent lifecycle points (hook config in `hooks/hooks.json` or `hooks.json`) |
| MCP servers | External tool integrations (config in `.mcp.json` at plugin root, uses `mcpServers` key) |

## Discovery

```text
User wants a plugin
 │
 ├─ 1. CHECK INSTALLED — list installed plugins
 │     Run in Extensions view: filter @agentPlugins
 │     Or check VS Code settings for chat.pluginLocations (local plugins)
 │     ├─ Found  → verify it meets the need → DONE
 │     └─ Not found → ↓
 │
 ├─ 2. SEARCH — find plugins in configured marketplaces
 │     Extensions view → search @agentPlugins <keyword>
 │     Or browse chat.plugins.marketplaces URLs
 │     Default marketplaces: github/copilot-plugins, github/awesome-copilot
 │     Additional: anthropics/claude-code
 │     ├─ Found → evaluate (see Quality Gate below) → install
 │     └─ Not found → ↓
 │
 ├─ 3. INSTALL FROM SOURCE — install directly from a Git URL
 │     Command: Chat: Install Plugin From Source
 │     Or: select + button on Plugins page of Chat Customizations editor
 │
 └─ 4. RECOMMEND ALTERNATIVE — no suitable plugin exists
       Consider: workspace skill (.github/skills/), MCP server, or custom tool
```

## Quality gate

Before recommending or installing a plugin, verify:

- [ ] **Publisher trust** — known publisher or verified organization
- [ ] **Maintenance** — updated within 12 months; no abandoned or archived repo
- [ ] **No credential exposure** — plugin does not require secrets beyond standard VS Code secret storage
- [ ] **Conflict check** — no naming collisions with existing workspace agents, skills, or hooks
- [ ] **Scope review** — plugin only requests the minimum capability it needs (check the contributed agent and skill metadata for unnecessary tool access)
- [ ] **Hook review** — if the plugin includes hooks, inspect hook scripts before enabling (hooks execute with VS Code's permissions)
- [ ] **MCP review** — if the plugin bundles MCP servers, verify server sources and tool capabilities

Plugins failing two or more checks are rejected.

## Conflict resolution

When a plugin contributes an agent or skill with the same name as a workspace file:

| Conflict type | Resolution |
|--------------|------------|
| Agent name collision | Workspace agent takes priority. VS Code shows source in tooltip. |
| Skill name collision | Project skills (`.github/skills/`) override plugin skills. |
| Hook collision | Workspace hooks fire alongside plugin hooks — check for duplicate behaviour. Most restrictive `PreToolUse` decision wins. |
| MCP server collision | Plugin MCP servers run alongside workspace servers. Disable via plugin toggle. |

Use the **Agent Debug Panel** (`Developer: Open Agent Debug Panel`) to see exactly which agents, skills, and hooks are loaded and from which source.

## Plugin hooks

Plugins can include hooks that fire at lifecycle events (`SessionStart`, `PreToolUse`, `PostToolUse`, `PreCompact`, `SubagentStart`, `SubagentStop`, `Stop`).

- Hook config location depends on format: `hooks/hooks.json` (Claude format) or `hooks.json` (Copilot format)
- Use `${CLAUDE_PLUGIN_ROOT}` in hook commands to reference scripts within the plugin directory
- Plugin hooks are implicitly trusted on install — review before enabling
- Disabling a plugin also disables its hooks

## Plugin MCP servers

Plugins can bundle MCP servers that start automatically when the plugin is enabled.

- Config in `.mcp.json` at plugin root using `mcpServers` key (not `servers`)
- Use `${CLAUDE_PLUGIN_ROOT}` in `command`, `args`, `cwd`, `env`, `url`, and `headers` fields
- Plugin MCP servers are implicitly trusted (no separate trust prompt)
- Disabling a plugin stops its MCP servers

## Settings reference

| Setting | Purpose |
|---------|---------|
| `chat.plugins.enabled` | Enable/disable plugin discovery (boolean) |
| `chat.plugins.marketplaces` | Git repositories serving as plugin marketplaces (array of owner/repo) |
| `chat.pluginLocations` | Local paths for plugin development/testing (map of path → boolean) |

## Workspace plugin recommendations

Projects can recommend plugins for team members:

```json
{
  "extraKnownMarketplaces": {
    "company-tools": {
      "source": { "source": "github", "repo": "your-org/plugin-marketplace" }
    }
  },
  "enabledPlugins": {
    "code-formatter@company-tools": true
  }
}
```

## Testing the template as a plugin

To preview how the template's agents, skills, hooks, and prompts appear as plugin-contributed customizations:

1. Clone the template repo (or use an existing local copy)
2. Add to VS Code settings:

   ```json
   "chat.pluginLocations": {
       "/path/to/copilot-instructions-template": true
   }
   ```

3. Reload VS Code — plugin-contributed agents appear in the Copilot dropdown
4. Verify: open the Agent Debug Panel to confirm agents, skills, and hooks are loaded
5. Check for conflicts with any workspace-level agents in `.github/agents/`

## Managing installed plugins

1. **List** — Extensions view → filter `@agentPlugins` to see all installed plugins
2. **Inspect** — select a plugin to see its contributed agents, skills, MCP servers, and commands
3. **Disable** — right-click → Disable (globally or per-workspace; also disables hooks and MCP servers)
4. **Remove** — right-click → Uninstall to fully remove
5. **Update** — `Extensions: Check for Extension Updates` or automatic every 24 hours

## Verify

- [ ] Requested plugin was found or a suitable alternative was identified
- [ ] Quality gate was applied before installation (including hook and MCP review)
- [ ] No unresolved naming conflicts between plugin and workspace agents/skills
- [ ] Agent Debug Panel confirms correct loading order and source attribution
