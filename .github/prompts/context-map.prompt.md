---
description: Map every file affected by a task before making any changes
argument-hint: Describe the task or feature you are about to implement
agent: agent
tools: [codebase, editFiles]
---

# Context Map

Before implementing any changes, analyse the codebase and produce a context map for the task described.

1. **Search** — Find all files directly related to the task (feature area, module name, keywords).
2. **Trace dependencies** — For each file found, identify imports/exports and transitive callers.
3. **Find tests** — Locate existing tests that cover the affected code.
4. **Spot patterns** — Find similar implementations elsewhere in the codebase to follow as reference.

## Output

Produce a context map in this format before writing any code:

```markdown
## Context Map

### Files to Modify
| File | Purpose | Changes Needed |
|------|---------|----------------|
| path/to/file | what it does | what must change |

### Dependencies (may need updates)
| File | Relationship |
|------|--------------|
| path/to/dep | imports X from modified file |

### Test Files
| Test | Coverage |
|------|----------|
| path/to/test | tests affected functionality |

### Reference Patterns
| File | Pattern to Follow |
|------|------------------|
| path/to/similar | example of the convention used |

### Risk Assessment
- [ ] Breaking changes to public API
- [ ] Database migrations needed
- [ ] Configuration changes required
- [ ] Parity files that must be kept in sync
```

Do not write any code until the map is reviewed and confirmed.
