---
name: webapp-testing
description: Set up browser testing — dual path with built-in browser tools (interactive) or Playwright (CI); detect framework, scaffold, verify
compatibility: ">=2.0"
---

# Web Application Testing

> Skill metadata: version "2.1"; license MIT; tags [testing, e2e, playwright, browser, ci, browser-tools, mcp]; compatibility ">=2.0"; recommended tools [codebase, editFiles, runCommands].

Set up browser testing for a web application. This skill offers three paths:

- **Path A — Built-in browser tools** (VS Code 1.110+): lightweight, interactive verification using VS Code's agentic browser tools. No dependencies to install. Ideal for development-time checks and exploratory testing.
- **Path B — Playwright**: full end-to-end testing framework with CI integration. Ideal for automated regression testing in CI/CD pipelines.
- **Path C — Playwright MCP server**: expose Playwright browser automation as MCP tools. Ideal for agent-driven testing workflows that need Playwright capabilities without a full test suite.

## Decision criteria

| Factor | Path A (Browser tools) | Path B (Playwright) | Path C (Playwright MCP) |
|--------|----------------------|---------------------|------------------------|
| **Setup effort** | Zero — built-in, no install | Moderate — install + configure | Low — add MCP server config |
| **CI integration** | No — interactive only | Yes — runs headless in CI | No — agent-driven only |
| **Test persistence** | No — conversational | Yes — test files committed to repo | No — on-demand via MCP tools |
| **Browser coverage** | Chromium only | Chromium + Firefox + WebKit | Chromium (default) |
| **Best for** | Quick verification, dev-time checks, debugging | Regression testing, PR gates, cross-browser | Agent-driven automation, scraping, form testing |
| **Requires** | `workbench.browser.enableChatTools: true` (Preview) | Node.js + Playwright package | `@playwright/mcp` package |

**Recommendation**: Use Path A for interactive verification during development, Path B for CI, Path C when you want Playwright browser control available as MCP tools to agents. They complement each other.

### Maintainer note

Use Path A when the agent only needs to inspect or click through a page during a live session in VS Code. It is the cheapest option and keeps browser access local to the current conversation.

Use Path C when website navigation should become part of the repo's repeatable agent tooling. Prefer it for agents that need reliable page navigation, form automation, or structured browser actions across Copilot, MCP-aware subagents, and CLI sessions.

Do not use Path C as a replacement for committed regression tests. When the behavior needs CI coverage or long-term safety, add Path B as well.

## When to activate

- User says "Set up e2e tests", "Add browser tests", "Add Playwright", "Test my web app", or "Check my web app"
- A web application exists but has no browser-level tests
- The `test-coverage-review` skill identifies missing e2e coverage

---

## Path A — Built-in Browser Tools

VS Code 1.110+ provides 10 agentic browser tools that allow Copilot to interact with web pages directly. These tools are experimental and require opt-in.

### A1. Enable browser tools

The user must enable the setting:

```json
{
  "workbench.browser.enableChatTools": true
}
```

> **Note**: This is a Preview feature. It may change or be removed in future VS Code releases.

### A2. Available browser tools

| Tool | Purpose |
|------|--------|
| `openBrowserPage` | Open a URL in a managed browser |
| `navigatePage` | Navigate to a new URL |
| `readPage` | Read page content (text, links, forms, structure) |
| `screenshotPage` | Capture a screenshot for visual verification |
| `clickElement` | Click a button, link, or interactive element |
| `hoverElement` | Hover over an element |
| `dragElement` | Drag and drop an element |
| `typeInPage` | Type text into input fields |
| `handleDialog` | Accept or dismiss browser dialogs |
| `runPlaywrightCode` | Run custom Playwright code snippets in the browser context |

### A3. Interactive verification workflow

1. Start the dev server (manually or via terminal)
2. Use `openBrowserPage` to open the app URL
3. Use `readPage` to verify page content loads correctly
4. Use `screenshotPage` for visual verification
5. Use `clickElement` / `typeInPage` to interact with forms, navigation
6. Use `readPage` after interactions to verify state changes

### A4. Example verification session

```text
User: "Check if my login page works"
Agent:
  1. openBrowserPage("http://localhost:3000/login")
  2. readPage() → verify login form elements exist
  3. typeInPage(selector: "#email", text: "test@example.com")
  4. typeInPage(selector: "#password", text: "testpass")
  5. clickElement(selector: "button[type=submit]")
  6. readPage() → verify redirect or error message
  7. screenshotPage() → capture visual state
```

### A5. Limitations

- Chromium only (no Firefox or WebKit)
- Interactive — results are conversational, not persisted as test files
- Cannot run in CI/CD pipelines
- Preview feature — may have stability issues
- Some dynamic content may not be fully accessible

---

## Path B — Playwright (CI-ready)

### B1. Detect the web framework

Scan the project for framework signals:

| Signal | Framework | Dev server command |
|--------|-----------|-------------------|
| `next.config.*`, `"next"` in deps | Next.js | `npx next dev` |
| `vite.config.*`, `"vite"` in deps | Vite (React/Vue/Svelte) | `npx vite` |
| `nuxt.config.*`, `"nuxt"` in deps | Nuxt | `npx nuxt dev` |
| `angular.json`, `"@angular/core"` in deps | Angular | `npx ng serve` |
| `svelte.config.*`, `"@sveltejs/kit"` in deps | SvelteKit | `npx vite dev` |
| `remix.config.*`, `"@remix-run/dev"` in deps | Remix | `npx remix dev` |
| `astro.config.*`, `"astro"` in deps | Astro | `npx astro dev` |

Also check `package.json` scripts for `"dev"`, `"start"`, or `"serve"` commands.

If no framework is detected, ask the user how to start the development server.

### B2. Install Playwright

```bash
npm init playwright@latest -- --quiet
```

This creates:

- `playwright.config.ts` — configuration file
- `tests/` — test directory
- `tests-examples/` — example tests (can be deleted)

If the user prefers a different package manager:

```bash
# pnpm
pnpm create playwright --quiet

# yarn
yarn create playwright --quiet

# bun
bunx create-playwright --quiet
```

### B3. Configure Playwright

Update `playwright.config.ts` for the detected framework:

```typescript
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? "github" : "html",
  use: {
    baseURL: "http://localhost:<PORT>",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "firefox", use: { ...devices["Desktop Firefox"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } },
  ],
  webServer: {
    command: "<DEV_SERVER_COMMAND>",
    url: "http://localhost:<PORT>",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
```

Replace `<PORT>` and `<DEV_SERVER_COMMAND>` with the detected values.

### B4. Write the first test

Create `tests/e2e/smoke.spec.ts` — a smoke test that verifies the app loads:

```typescript
import { test, expect } from "@playwright/test";

test("home page loads successfully", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveTitle(/.+/);
  // Verify the page is not an error page
  await expect(page.locator("body")).not.toContainText("500");
  await expect(page.locator("body")).not.toContainText("Internal Server Error");
});

test("navigation is functional", async ({ page }) => {
  await page.goto("/");
  // Verify at least one link or navigation element exists
  const links = page.locator("a[href]");
  await expect(links.first()).toBeVisible();
});
```

If the project has a login page, authentication flow, or other critical paths identified in Step 1, write targeted tests for those too.

### B5. Verify tests pass

```bash
npx playwright test
```

Expected output:

- All tests pass on at least one browser
- No flaky tests (run twice to confirm)
- HTML report is generated (`npx playwright show-report`)

If tests fail:

- Check that the dev server starts correctly
- Verify the `baseURL` matches the actual dev server port
- Ensure selectors match actual page elements

### B6. Add CI workflow

Create `.github/workflows/playwright.yml`:

```yaml
name: Playwright Tests
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    timeout-minutes: 60
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
      - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4
        with:
          node-version: lts/*
      - name: Install dependencies
        run: npm ci
      - name: Install Playwright browsers
        run: npx playwright install --with-deps
      - name: Run Playwright tests
        run: npx playwright test
      - uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4
        if: ${{ !cancelled() }}
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 30
```

### B7. Update project files

- Add to `.gitignore`:

  ```text
  # Playwright
  /test-results/
  /playwright-report/
  /blob-report/
  /playwright/.cache/
  ```

- Add convenience scripts to `package.json`:

  ```json
  {
    "scripts": {
      "test:e2e": "playwright test",
      "test:e2e:ui": "playwright test --ui",
      "test:e2e:report": "playwright show-report"
    }
  }
  ```

## Path C — Playwright MCP Server

The `@playwright/mcp` package exposes Playwright browser automation as MCP tools, allowing agents to navigate pages, take screenshots, click elements, fill forms, and execute JavaScript — all through the MCP protocol.

### C1. Install and configure

Add to `.vscode/mcp.json`:

```json
{
  "servers": {
    "playwright": {
      "command": "npx",
      "args": [
        "-y",
        "@playwright/mcp@latest",
        "--headless",
        "--browser=chromium"
      ],
      "disabled": true
    }
  }
}
```

Remove `"disabled": true` when you want the server to start. If the repo uses
agent-level `mcp-servers` allowlists, add `playwright` only to the agents that
should be allowed to drive websites.

### C2. Available MCP tools

The server exposes tools including: `browser_navigate`, `browser_screenshot`, `browser_click`, `browser_type`, `browser_select_option`, `browser_hover`, `browser_evaluate`, `browser_handle_dialog`, `browser_tab_list`, `browser_tab_create`, `browser_tab_close`, `browser_pdf_save`, `browser_console_messages`.

### C3. When to prefer over Path A

- You need Playwright's engine (more reliable element targeting, network interception)
- The agent workflow benefits from structured MCP tool calls rather than ad-hoc browser tool usage
- You want the same automation capabilities available to Copilot CLI or external agents via MCP bridge

### C4. Limitations

- No built-in CI integration (use Path B for CI)
- Tests are not persisted as files — they run on-demand through agent interaction
- Requires Node.js runtime for the MCP server process

## Verify

- [ ] Path A (browser tools): `workbench.browser.enableChatTools` is enabled when using built-in tools
- [ ] Path A (browser tools): page opens, key action works, and a screenshot is captured
- [ ] Path B (Playwright): `npx playwright test` passes on at least Chromium
- [ ] Path B (Playwright): CI workflow file is valid YAML (`actionlint .github/workflows/playwright.yml`)
- [ ] Path B (Playwright): `.gitignore` excludes Playwright artifacts
- [ ] Path B (Playwright): `package.json` has `test:e2e` script
- [ ] Path C (Playwright MCP): `@playwright/mcp` entry exists in `.vscode/mcp.json`
- [ ] Path C (Playwright MCP): `browser_navigate` tool is available after server starts
