---
description: Refactor selected code using PDCA cycle and Lean waste elimination
argument-hint: Select code first, or name the file and waste category to target
agent: agent
tools: [editFiles, runCommands, codebase]
---

# Refactor Code

Refactor the selected code following Lean principles from §1 and the PDCA cycle from §3.

1. **Plan**: Identify the specific waste (§6 W1–W16) or baseline violation (§2) being addressed. State the goal and expected LOC delta.
2. **Do**: Perform the refactoring. Preserve all existing behaviour — no feature changes.
3. **Check**: Run `bash tests/run_simple_tests.sh && echo "type-check: N/A"` and confirm no regressions.
4. **Act**: If baselines are exceeded, address them. Summarise what changed and why.

Do not add features, change APIs, or modify tests unless the refactoring requires it.
