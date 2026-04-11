---
name: skill-creator
description: Create a new agent skill following the Agent Skills open standard
compatibility: ">=1.4"
---

# Skill Creator

> Skill metadata: version "1.2"; license MIT; tags [meta, authoring, skill, scaffold]; compatibility ">=1.4"; recommended tools [codebase, editFiles, runCommands].

Create a new agent skill that follows the [Agent Skills](https://agentskills.io) open standard and the project's §12 Skill Protocol.

## When to use

- The user asks to "create a skill", "write a skill", or "add a new skill"
- A workflow is being repeated manually and would benefit from codification
- An online skill was found but needs significant adaptation

> **Tip**: VS Code 1.110+ has a built-in `/create-skill` slash command that generates a basic scaffold. This skill provides additional Lean/Kaizen guidance: waste-aware naming, PDCA verification steps, and quality gate checks.

## Steps

1. **Clarify scope** — Ask the user: *"What workflow should this skill encode? Describe the trigger and the desired outcome in one sentence."*

2. **Choose a name** — Use a verb-noun kebab phrase describing the workflow (e.g., `review-dependencies`, `scaffold-api-route`). The name becomes the directory name under `.github/skills/`. Rules: 1–64 chars, lowercase alphanumeric and hyphens only, no leading/trailing/consecutive hyphens, must match directory name.

3. **Write the frontmatter** — Create `.github/skills/<name>/SKILL.md` with the full Agent Skills-compatible header:

   ```yaml
   ---
   name: <kebab-name>
   description: <one precise sentence - this is how the agent discovers the skill>
   metadata:
     author: <org or user>
     version: "1.0"
   ---
   ```

   Optional frontmatter fields (add only when relevant):

   | Field | When to include |
   |-------|----------------|
   | `user-invocable` | Set to `false` to hide from the `/` menu while still allowing auto-load |
   | `disable-model-invocation` | Set to `true` to require manual `/` invocation only |
   | `allowed-tools` | Space-delimited pre-approved tools (experimental) |
   | `compatibility` | Environment requirements (e.g., `">=3.2"`, `"Requires Python 3.14+"`) |

   Do not add unsupported top-level keys such as `stacks`. If you want human-readable stack hints, put them in the description or the `Skill metadata` note instead.

   Then add a note immediately after the `# <Name>` heading:

   ```markdown
   > Skill metadata: version "1.0"; license MIT; tags [<2-5 keywords matching common task descriptions>]; compatibility ">=<current template version>"; recommended tools [codebase, editFiles].
   ```

4. **Write the body** — Structure as:
   - **Title** (`# <Name>`) — human-readable heading.
   - **When to use** — bullet list of trigger conditions and contra-indications.
   - **Steps** — numbered list with clear action verbs. Each step should be independently verifiable.
   - **Verify** — a final step that confirms the skill completed correctly.

5. **Apply authoring rules** (from §12):
   - One skill, one workflow — if you need "and", split it.
   - No hardcoded paths — use relative references and contextual lookups.
   - Idempotent — running the skill twice produces the same result.
   - Steps, not prose — the agent follows these literally.

6. **Apply progressive disclosure** (from Agent Skills spec):
   - Metadata (~100 tokens): `name` and `description` are loaded at startup for all skills.
   - Instructions (<5000 tokens recommended): the full `SKILL.md` body is loaded on activation.
   - Resources (on demand): reference files in `scripts/`, `references/`, `assets/` subdirectories — loaded only when needed.
   - Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files.

7. **Save** — Write the file.

8. **Validate** — If the `skills-ref` CLI is available, run `skills-ref validate .github/skills/<name>` to check frontmatter and naming. Otherwise verify manually.

9. **Run tests** — Verify the new skill file passes any applicable test suite checks.

## Verify

- [ ] `.github/skills/<name>/SKILL.md` exists
- [ ] Frontmatter has both `name` and `description` fields
- [ ] `name` field matches directory name (lowercase, hyphens only)
- [ ] Body has "When to use" and "Steps" sections
- [ ] Steps are numbered with clear action verbs
- [ ] Final step is a verification check
- [ ] File is under 500 lines
