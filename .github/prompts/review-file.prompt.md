---
description: Review a file for waste categories, baseline violations, and coding convention issues
argument-hint: Open the file to review, or name it here
agent: ask
tools: [codebase]
---

# Review File

Review the current file using the §5 Review Mode protocol.

1. Read the file in full before making any observations.
2. For each finding, classify by:
   - **Severity**: critical / major / minor / advisory
   - **Waste category**: W1–W16 from §6 (or "none" if not applicable)
3. Check §2 baselines: file LOC, dependency count, type errors.
4. Note any patterns that violate §4 coding conventions.
5. Produce a structured report — do not apply fixes.

Format findings as a table:

| # | Severity | Waste | Line(s) | Finding | Suggestion |
|---|----------|-------|---------|---------|------------|
