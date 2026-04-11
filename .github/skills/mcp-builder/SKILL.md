---
name: mcp-builder
description: Create a new MCP server — clarify purpose, choose transport, scaffold, implement, test, and register
compatibility: ">=2.0"
---

# MCP Server Builder

> Skill metadata: version "1.2"; license MIT; tags [mcp, server, tool, integration, scaffold]; compatibility ">=2.0"; recommended tools [codebase, editFiles, runCommands].

Build a new Model Context Protocol (MCP) server from scratch. This skill walks through the full lifecycle: clarifying the server's purpose, choosing transport, scaffolding, implementing tools/resources, testing, and registering the server in `.vscode/mcp.json`.

## When to activate

- User says "Build an MCP server", "Create an MCP server for ...", or "I need an MCP integration for ..."
- A task requires external data or capabilities not covered by existing MCP servers
- The §13 MCP decision tree reaches step 4 (BUILD)

## Workflow

### 1. Clarify purpose

Ask the user:

- **What capability** does this server provide? (e.g., "query our Postgres database", "fetch Jira tickets", "interact with Slack")
- **What tools** should it expose? (list 1–5 tool names with one-sentence descriptions)
- **What resources** should it expose, if any? (e.g., database schemas, API documentation)
- **Does it need credentials?** If yes, which environment variables?

### 2. Choose transport

| Transport | When to use | Trade-offs |
|-----------|------------|------------|
| **stdio** (recommended) | Local servers, same machine as VS Code | Simplest setup, no network config, most secure |
| **SSE** | Remote servers, shared team servers | Requires HTTPS in production, more complex deployment |
| **Streamable HTTP** | New servers targeting latest MCP spec | Newest transport, best for stateless operations |

Default to **stdio** unless the user has a specific reason for a remote transport.

### 3. Scaffold the server

Choose the implementation language based on the project's primary stack:

**TypeScript/JavaScript** (recommended for most projects):

```bash
mkdir -p .mcp-servers/<server-name>
cd .mcp-servers/<server-name>
npm init -y
npm install @modelcontextprotocol/sdk zod
npm install --save-dev tsx typescript @types/node
```

Create the entry point (`src/index.ts` or `index.js`):

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({
  name: "<server-name>",
  version: "1.0.0",
});

// Tools are registered here (Step 4)

const transport = new StdioServerTransport();
await server.connect(transport);
```

**Python** (alternative):

```bash
mkdir -p .mcp-servers/<server-name>
cd .mcp-servers/<server-name>
uv init && uv add mcp
```

### 4. Implement tools

For each tool identified in Step 1:

1. Define the input schema using Zod (TypeScript) or Pydantic (Python)
2. Implement the handler function
3. Register with the server:

```typescript
server.tool(
  "<tool-name>",
  "<one-sentence description>",
  { param: z.string().describe("what this parameter does") },
  async ({ param }) => {
    // Implementation
    return { content: [{ type: "text", text: result }] };
  }
);
```

Rules:

- One tool, one action — keep tools focused
- Validate all inputs with schemas
- Return structured content (text or JSON)
- Handle errors gracefully — return error content, don't throw

### 5. Test with MCP Inspector

```bash
npx @modelcontextprotocol/inspector tsx .mcp-servers/<server-name>/src/index.ts
```

> **Python alternative**: `npx @modelcontextprotocol/inspector python .mcp-servers/<server-name>/main.py`

Verify:

- [ ] Server starts without errors
- [ ] Each tool appears in the inspector's tool list
- [ ] Each tool executes correctly with sample inputs
- [ ] Error cases return meaningful messages

### 6. Add resources and prompts (optional)

Beyond tools, MCP servers can expose:

| Capability | Purpose | VS Code access |
|------------|---------|---------------|
| **Resources** | Read-only data context (files, schemas, API docs) | Chat → Add Context → MCP Resources |
| **Prompts** | Pre-configured prompt templates | Type `/<server>.<prompt>` in chat |
| **MCP Apps** | Interactive UI (forms, visualisations, drag-and-drop) | Rendered inline in chat |

Add resources when the server has data the agent should reference. Add prompts when there are common task patterns. Consider MCP Apps (using `@modelcontextprotocol/ext-apps` SDK) for interactive output.

### 7. Register in `.vscode/mcp.json`

Add the server to the project's MCP configuration:

```json
{
  "<server-name>": {
    "type": "stdio",
    "command": "npx",
    "args": ["tsx", ".mcp-servers/<server-name>/src/index.ts"],
    "env": {
      "API_KEY": "${env:SERVER_NAME_API_KEY}"
    }
  }
}
```

> **Note**: For production use, compile TypeScript first (`npx tsc`) and reference the compiled JS output instead of running `tsx` at runtime.

### 8. Document

- Add the server to the §13 Available servers table in `.github/copilot-instructions.md`
- If the server is reusable across projects, consider publishing to an MCP registry

### 9. Distribute via plugin (optional)

To bundle the server as part of an agent plugin for sharing:

1. Create `.mcp.json` at the plugin root (uses `mcpServers` key, not `servers`):

   ```json
   {
     "mcpServers": {
       "<server-name>": {
         "command": "${CLAUDE_PLUGIN_ROOT}/servers/<server-name>",
         "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"]
       }
     }
   }
   ```

2. Use `${CLAUDE_PLUGIN_ROOT}` for all path references within the plugin
3. Plugin MCP servers start automatically on enable and are implicitly trusted

## Verify

- [ ] Server starts via stdio and responds to `initialize` request
- [ ] All tools execute correctly in MCP Inspector
- [ ] Resources and prompts are discoverable (if implemented)
- [ ] `.vscode/mcp.json` is valid JSON with the new server entry
- [ ] §13 Available servers table is updated
