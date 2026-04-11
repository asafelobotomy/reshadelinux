---
name: create-adr
description: Create an Architectural Decision Record (ADR) to document a significant design or technology choice
compatibility: ">=1.4"
---

# Create Architectural Decision Record

> Skill metadata: version "1.0"; license MIT; tags [documentation, architecture, decision, adr]; compatibility ">=1.4"; recommended tools [editFiles, codebase].

Create a structured ADR document that captures the context, decision, consequences, and alternatives for a significant architectural choice.

## When to use

- The user asks to "create an ADR", "document this decision", or "record why we chose X"
- A significant technology, framework, pattern, or architectural choice was just made
- A design decision needs to be preserved for future maintainers and AI agents
- A rejected option needs to be documented to prevent re-litigating it later

## When NOT to use

- Trivial implementation details (naming, minor refactors) — those belong in commit messages
- Decisions that are already obvious from the code itself
- A full project design doc is needed (that is a specification, not an ADR)

## Steps

1. **Gather inputs** — Collect from the user (or infer from conversation context):
   - Decision title (verb phrase: "Use X for Y")
   - Context: the problem, constraints, and forces driving the decision
   - Decision: what was chosen and why
   - Alternatives: what else was considered and why each was rejected
   - Stakeholders: teams or roles affected

   If any required input is missing and cannot be inferred, ask before proceeding.

2. **Determine sequence number** — List existing files in `docs/adr/` (create directory if absent). Use the next 4-digit number (`0001`, `0002`, …).

3. **Write the ADR** — Save to `docs/adr/adr-NNNN-<title-slug>.md` using the template below. Replace all bracketed placeholders.

4. **Confirm** — Show the created file path to the user.

## ADR Template

```markdown
---
title: "ADR-NNNN: [Decision Title]"
status: "Proposed"
date: "YYYY-MM-DD"
authors: "[Stakeholder Names/Roles]"
tags: ["architecture", "decision"]
supersedes: ""
superseded_by: ""
---

# ADR-NNNN: [Decision Title]

## Status

**Proposed** | Accepted | Rejected | Superseded | Deprecated

## Context

[Problem statement, technical constraints, business requirements, and environmental factors
requiring this decision.]

## Decision

[Chosen solution with clear rationale for selection.]

## Consequences

### Positive

- **POS-001**: [Beneficial outcomes and advantages]
- **POS-002**: [Performance, maintainability, scalability improvements]

### Negative

- **NEG-001**: [Trade-offs, limitations, drawbacks]
- **NEG-002**: [Technical debt or complexity introduced]

## Alternatives Considered

### [Alternative 1 Name]

- **ALT-001**: **Description**: [Brief technical description]
- **ALT-002**: **Rejection Reason**: [Why this option was not selected]

### [Alternative 2 Name]

- **ALT-003**: **Description**: [Brief technical description]
- **ALT-004**: **Rejection Reason**: [Why this option was not selected]

## Implementation Notes

- **IMP-001**: [Key implementation considerations]
- **IMP-002**: [Migration or rollout strategy if applicable]
- **IMP-003**: [Monitoring and success criteria]

## References

- **REF-001**: [Related ADRs]
- **REF-002**: [External documentation]
- **REF-003**: [Standards or frameworks referenced]
```
