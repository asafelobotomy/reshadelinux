---
name: mcp-management
description: Configure and manage Model Context Protocol servers for external tool access
compatibility: ">=1.4"
---

# MCP Management

> Skill metadata: version "1.1"; license MIT; tags [mcp, servers, configuration, integration]; compatibility ">=1.4"; recommended tools [codebase, editFiles, fetch].

MCP (Model Context Protocol) is GA in VS Code as of v1.102. MCP servers provide tools, resources, and prompts beyond built-in capabilities. Configuration lives in `.vscode/mcp.json` (workspace-scoped) or profile-level `mcp.json` (user-scoped).

## When to use

- The user asks to configure, add, list, or check MCP servers
- You need to determine which MCP servers are available
- A task would benefit from an external tool not yet configured

## Configuration locations

| Location | Scope | When to use |
|----------|-------|-------------|
| `.vscode/mcp.json` | Workspace | Project-specific servers shared via version control |
| Profile-level `mcp.json` | User | Personal servers available across all workspaces |
| `settings.json` `"mcp"` key | User/Workspace | Alternative to standalone `mcp.json` |
| Dev container `customizations.vscode.mcp` | Container | Per-container MCP servers |

**VS Code commands:**

- `MCP: Open Workspace Configuration` — edit `.vscode/mcp.json`
- `MCP: Open User Configuration` — edit profile-level `mcp.json`

## Server tiers

| Tier | Default servers | When to enable | Configuration |
|------|----------------|-----------------|---------------|
| Always-on | filesystem, git | Every project — core development tools | Enabled by default in `.vscode/mcp.json` |
| External access | github, fetch | When GitHub or web access is needed | `github` uses VS Code OAuth (HTTP remote, no PAT required); `fetch` needs no credentials |
| Documentation | context7 | Any project using third-party libraries | HTTP remote, free tier requires no auth; optional API key for higher rate limits |

## Available servers

| Server | Tier | Transport | Purpose |
|--------|------|-----------|---------|
| `@modelcontextprotocol/server-filesystem` | Always-on | `npx` (stdio) | File operations within the workspace; supports OS-level sandboxing |
| `mcp-server-git` | Always-on | **`uvx`** (stdio, Python) | Git history, diffs, and branch operations |
| `github/github-mcp-server` | Credentials | **HTTP remote** (`https://api.githubcopilot.com/mcp/`) | GitHub API — issues, PRs, repos, Actions, CI/CD, security alerts, Dependabot |
| `mcp-server-fetch` | Credentials | **`uvx`** (stdio, Python) | HTTP fetch for web content and APIs |
| `@upstash/context7-mcp` | Documentation | **HTTP remote** (`https://mcp.context7.com/mcp`) | Live, version-specific library documentation — prevents hallucinated or outdated APIs |

> **Removed (v3.2.0):** `@modelcontextprotocol/server-memory` — replaced by VS Code's built-in memory tool (`/memories/`), which provides persistent storage with three scopes: user (cross-workspace), session (conversation), and repository.
>
> **Archived (deprecated):** `@modelcontextprotocol/server-github` (npm) — replaced by `github/github-mcp-server` remote HTTP server. Do not add new configurations using the archived npm package.

## Stack-specific servers

The servers below are not included in the base consumer template. Add them to `.vscode/mcp.json` based on your project's technology stack.

| Stack | Server | Transport | Notes |
|-------|--------|-----------|-------|
| Browser / UI testing | `@playwright/mcp` (Microsoft) | `npx -y @playwright/mcp@latest` | Accessibility-tree-based; no vision model needed |
| PostgreSQL | Search MCP Marketplace for `postgres` | varies | Official reference server is archived; use marketplace for maintained replacement |
| SQLite | Search MCP Marketplace for `sqlite` | varies | Same — official archived; find active replacement |
| Redis | Search MCP Marketplace for `redis` | varies | Same |
| Docker / containers | Search MCP Marketplace for `docker` | varies | Several options; evaluate trust and permissions carefully |
| AWS | Search MCP Marketplace for `aws` | varies | Use fine-grained IAM credentials via `${env:}`, never hardcode |

Discover servers: `code.visualstudio.com/mcp` (gallery) · `registry.modelcontextprotocol.io` (official registry) · `glama.ai` · `smithery.ai`

### Optional: Sequential Thinking

`@modelcontextprotocol/server-sequential-thinking` (`npx`) — adds a structured step-by-step reasoning tool. Useful for complex planning or debugging sessions that benefit from explicit thought chains. Not project-specific; consider adding to your **user-level** `mcp.json` rather than the workspace config.

Configuration:

```json
"sequentialThinking": {
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
}
```

## MCP capabilities (GA since v1.102)

MCP servers can expose four capability types:

| Capability | Description | Agent interaction |
|-----------|-------------|-------------------|
| **Tools** | Functions the agent can invoke (e.g., query database, call API) | Agent calls tools directly |
| **Resources** | Data sources the agent can read (e.g., database schemas, config files) | Agent reads from `#` context menu |
| **Prompts** | Reusable prompt templates provided by the server | Available via `/` slash commands |
| **MCP Apps** | Interactive UI components (forms, visualisations, drag-and-drop) | Rendered inline in chat responses |
| **Sampling** | Server requests the agent to generate text on its behalf | Agent responds to server requests |

Additional features: **elicitations** (server requests user input via the agent), **MCP auth** (OAuth/token flows for secure server connections).

## Server discovery

- **MCP gallery**: In the Extensions view, search `@mcp` to browse and install servers directly (installs to user profile or workspace)
- **MCP Marketplace**: Browse and install servers from `code.visualstudio.com/mcp`
- **Official registry**: `github.com/modelcontextprotocol/servers`
- **Community registries**: `mcp.so`, `glama.ai`, `smithery.ai`
- **Agent plugins**: MCP servers can be bundled inside agent plugins (`@agentPlugins` in Extensions view)

## Adding a new server

Before adding any MCP server:

1. Check if a built-in tool or existing MCP server already covers the need
2. Search the MCP Marketplace (`code.visualstudio.com/mcp`) and official registry
3. Check for `npx` vs `uvx` vs HTTP remote transport — prefer HTTP remote for officially hosted servers (no local process, OAuth-managed auth)
4. Add to `.vscode/mcp.json` (workspace) or profile `mcp.json` (user) with appropriate tier
5. For credentials-required stdio servers, use `${input:}` or `${env:}` variable syntax — never hardcode secrets; HTTP remote servers use VS Code's built-in OAuth where supported
6. For stdio servers on Linux/macOS, add `sandboxEnabled: true` with `sandbox.filesystem.denyRead` rules for credential directories (`~/.ssh`, `~/.gnupg`, `~/.aws`) as a defence-in-depth measure against prompt injection. Optionally add `sandbox.network.allowedDomains` to restrict outbound network access
7. In consumer template repos, keep optional servers such as `github`, `fetch`, and `context7` present in `.vscode/mcp.json` but disabled by default until setup or update explicitly enables them
8. Agent files can declare least-privilege MCP access using the `mcp-servers` frontmatter field. Treat this as forward-compatible policy metadata: GitHub Copilot cloud agents document support for the field today, while local VS Code agent support may lag behind

### Sandbox compatibility (Linux)

On immutable Linux distros (Fedora Atomic/Bazzite/Silverblue, NixOS) where `/home` is a symlink to `/var/home`, the `bwrap` sandbox rejects `allowWrite` paths because symlink resolution points outside the expected location. Detect at setup time:

```bash
[[ "$(readlink -f /home)" != "/home" ]] && echo "immutable" || echo "standard"
```

- **standard**: use sandboxed config (`sandboxEnabled: true` + `allowWrite`/`denyRead` rules)
- **immutable**: omit `sandboxEnabled`, `sandbox`, and the top-level `sandbox` block entirely

## Auto-start

Set `"chat.mcp.autostart": "newAndOutdated"` in `.vscode/settings.json` so MCP servers start automatically when a chat message is sent. This eliminates the need to manually click the refresh/start button each session. VS Code will show a trust dialog the first time a new or changed server auto-starts.

## CLI and external agent access

As of VS Code 1.113, MCP servers configured in `.vscode/mcp.json` are automatically bridged to Copilot CLI and Claude agents. No additional configuration is required — servers registered in the workspace or user profile are available to all agent runtimes.

## Settings Sync

With Settings Sync enabled, MCP server configurations can be synchronised across devices. Run `Settings Sync: Configure` and enable the **MCP Servers** option to maintain a consistent development environment across machines.

## Subagent MCP use

Subagents inherit access to all configured MCP servers. A subagent may invoke any server already in `.vscode/mcp.json`. To **add** a new server, the subagent must flag the proposal to the parent agent, which confirms before modifying `.vscode/mcp.json`.
