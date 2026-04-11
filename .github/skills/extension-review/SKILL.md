---
name: extension-review
description: Audit VS Code extensions against the current project stack and recommend keep/add/remove actions
compatibility: ">=3.2"
---

# Extension Review

> Skill metadata: version "1.1"; license MIT; tags [extensions, vscode, audit, tooling, review, plugins]; compatibility ">=3.2"; recommended tools [codebase, fetch, runCommands].

Review the current project's VS Code extensions and recommend what to keep, add, or remove based on the actual stack in the repository.

## When to use

- The user asks to "review extensions", "check my extensions", or "audit VS Code extensions"
- The user wants recommended extensions for the current project
- The user wants to identify duplicate, stale, or irrelevant extensions

## When NOT to use

- The user already knows the exact extension they want to install
- The task is to edit `.vscode/extensions.json` directly without an audit first

## Steps

1. **Get the installed list** - Try to enumerate extensions automatically using the `runCommands` tool:

   ```bash
   code --list-extensions --show-versions | sort
   ```

   If the command fails (e.g., `code` CLI not on PATH or terminal unavailable), fall back to asking the user to run `code --list-extensions | sort` and paste the output.

2. **Profile check** - Check whether a repo-specific VS Code Profile is active:
   - Run `code --list-extensions | grep -i copilot-profile-tools` to detect the companion extension.
   - **If installed and the current runtime exposes an active-profile helper tool**: use it. If the user is on the Default Profile, recommend creating a dedicated Empty Profile (`code . --profile "ProjectName"`) before proceeding.
   - **If installed but no helper tool is available**: ask the user to confirm the active profile from the Profiles UI before drawing conclusions.
   - **If not installed**: note that profile detection is limited. Recommend creating a repo-specific profile to isolate extensions from other projects.

3. **Read workspace recommendations** - Inspect `.vscode/extensions.json` and `.vscode/settings.json` if they exist.

4. **Detect the stack** - Scan the repository for the actual language, runtime, linter, formatter, test, and config signals that determine which extensions are relevant.

5. **Audit agent plugins** - Search `@agentPlugins` in the Extensions view to list installed agent plugins. Agent plugins bundle skills, agents, hooks, and MCP servers. Check for:
   - Plugins that overlap with installed extensions (duplicate functionality)
   - Plugins that contribute MCP servers already configured in `.vscode/mcp.json`
   - Plugins no longer relevant to the current stack

6. **Check MCP-contributing extensions** - Some extensions register MCP servers automatically. Cross-reference `.vscode/mcp.json` with extension-contributed servers to identify:
   - Extensions whose MCP servers duplicate standalone MCP server configs
   - Extensions installed only for their MCP server that could be replaced by a lightweight MCP config

7. **Compare installed vs needed** - Build three groups:
   - **Keep** - installed and relevant
   - **Recommended additions** - not installed but clearly useful for the detected stack
   - **Consider removing** - installed but irrelevant, duplicate, deprecated, or superseded

8. **Handle unknown stacks carefully** - If the project uses a tool not covered by the built-in stack table, research the VS Code Marketplace and only recommend candidates that meet all three checks:
   - install count > 100k
   - rating >= 4.0
   - updated within the last 12 months

9. **Persist new mappings** - If an unknown stack produces a qualified extension recommendation, append the new stack-to-extension mapping to `.copilot/workspace/knowledge/TOOLS.md` under `Extension registry`.

10. **Present the report** - Use this structure:

    ```markdown
    ## Extension Review - <project>

    ### Keep
    - `publisher.extension` - why it still fits

    ### Recommended additions
    - `publisher.extension` - what it provides | why needed
      Install: Ctrl+P -> `ext install publisher.extension`

    ### Consider removing
    - `publisher.extension` - duplicate / unused language / deprecated

    ### Agent plugins
    - `plugin-name` - keep / remove / overlaps with `publisher.extension`

    ### Notes
    - stack signals discovered
    - unknown stacks researched
    - extension registry updates made
    - MCP server overlaps identified
    ```

11. **Wait** - Do not modify `.vscode/extensions.json` or install/uninstall anything until the user explicitly asks.

## Verify

- [ ] Installed extensions were obtained (auto-detected or user-provided)
- [ ] Profile status was checked and repo-specific profile recommended if needed
- [ ] Workspace recommendations were checked when present
- [ ] Agent plugins were audited for overlap and relevance
- [ ] MCP-contributing extensions were cross-referenced with `.vscode/mcp.json`
- [ ] Every recommendation is tied to an actual stack signal in the repo
- [ ] Unknown-stack recommendations passed the install/rating/recency quality gate
- [ ] No extension was installed, uninstalled, or written automatically
