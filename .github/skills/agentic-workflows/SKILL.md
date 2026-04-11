---
name: agentic-workflows
description: Set up and manage GitHub Actions workflows that use Copilot coding agents for automated PR handling and issue resolution
compatibility: ">=3.2"
---

# Agentic Workflows

> Skill metadata: version "1.0"; license MIT; tags [github-actions, automation, ci, agents, pull-requests]; compatibility ">=3.2"; recommended tools [codebase, editFiles, runCommands, githubRepo].

Set up GitHub Actions workflows that invoke Copilot coding agents to automate tasks like issue resolution, PR creation, and code review — triggered by GitHub events rather than interactive chat.

## When to use

- The user asks to "automate issue handling", "set up agentic workflows", or "use Copilot in CI"
- The user wants agents to respond to GitHub events (issues, PRs, comments)
- The user says "auto-fix issues", "agent-driven PRs", or "coding agent in Actions"

## When NOT to use

- The user wants interactive Copilot chat — that is the default experience, not a workflow
- The user wants to fix a failing CI pipeline — use the **fix-ci-failure** skill instead
- The CI system is not GitHub Actions — this skill is GitHub-specific

## Prerequisites

- GitHub Copilot must be enabled for the repository or organization
- The repository must use GitHub Actions
- The `copilot-setup-steps.yml` workflow must exist (provides agent environment setup)
- Appropriate permissions must be configured on the workflow (`contents: write`, `pull-requests: write`, `issues: read`)

## Concepts

### Copilot coding agent

A headless Copilot session triggered by a GitHub Actions workflow. It runs without interactive prompts, using a Codex-class model. The agent reads the issue or event context, plans a fix, implements it, and opens a PR.

### copilot-setup-steps.yml

A reusable workflow that configures the agent's environment (runtime, dependencies, tools). It runs before the agent starts. The template ships one at `template/copilot-setup-steps.yml`.

### Event triggers

| Trigger | Use case |
|---------|----------|
| `issues.labeled` | Auto-assign agent when a specific label is added |
| `issue_comment.created` | Agent responds to a command comment (e.g., `/fix`) |
| `pull_request.opened` | Auto-review new PRs |
| `workflow_dispatch` | Manual agent invocation |

## Steps

1. **Verify setup steps exist** — Check that `.github/workflows/copilot-setup-steps.yml` exists. If not, fetch and write it:

   ```text
   https://raw.githubusercontent.com/asafelobotomy/copilot-instructions-template/main/template/copilot-setup-steps.yml
   ```

2. **Choose the trigger pattern** — Ask the user which event should invoke the agent:

   | Pattern | Workflow trigger | Agent receives |
   |---------|-----------------|----------------|
   | Label-based | `issues.labeled` | Issue body and comments |
   | Comment-based | `issue_comment.created` | Comment text and issue context |
   | PR review | `pull_request.opened` | PR diff and description |
   | Manual | `workflow_dispatch` | User-provided inputs |

3. **Create the workflow** — Write `.github/workflows/copilot-agent.yml`:

   ```yaml
   name: Copilot Agent
   on:
     issues:
       types: [labeled]

   jobs:
     agent:
       if: github.event.label.name == 'copilot'
       runs-on: ubuntu-latest
       permissions:
         contents: write
         pull-requests: write
         issues: read
       steps:
         - uses: actions/checkout@v4
         - uses: ./.github/workflows/copilot-setup-steps.yml
         # The Copilot coding agent handles the rest automatically
   ```

   Adjust the trigger and condition based on the user's choice in step 2.

4. **Configure guardrails** — Ensure the workflow respects project conventions:
   - The agent inherits `.github/copilot-instructions.md` automatically
   - Add a label filter to prevent accidental triggers
   - Set appropriate `permissions` — principle of least privilege
   - Consider adding a `concurrency` group to prevent parallel agent runs on the same issue

5. **Test the workflow** — Create a test issue, apply the trigger label (or comment), and verify the agent picks it up. Check the Actions tab for the workflow run.

6. **Document the trigger** — Add the trigger phrase and label to `AGENTS.md` so team members know how to invoke the agent.

## Security considerations

- Never grant `permissions: write-all` — scope to exactly what the agent needs
- Use label-based triggers with restricted label permissions to prevent unauthorized invocations
- Review agent-created PRs before merging — automated does not mean trusted
- Consider branch protection rules that require human approval for agent PRs

## Waste categories

| Risk | Waste code | Mitigation |
|------|-----------|------------|
| Agent runs on irrelevant issues | W1 Overproduction | Use specific labels and filters |
| Agent waits for human review | W2 Waiting | Enable auto-merge for low-risk changes only |
| Duplicate agent runs | W5 Inventory | Add `concurrency` groups |
| Over-trusting agent output | W16 Over-trust | Require human review on all agent PRs |
