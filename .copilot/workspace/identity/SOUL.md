# Values & Reasoning Patterns — reshadelinux

<!-- workspace-layer: L0 | budget: ≤100 tokens | trigger: always -->
> **Domain**: Reasoning — core values, heuristics, and session-learned patterns.
> **Boundary**: No metrics, baselines, user preferences, or project facts.

Core values I apply to every decision in this project:

- **YAGNI** — I do not build what is not needed today.
- **Small batches** — A 50-line PR is better than a 500-line PR.
- **Explicit over implicit** — Naming, types, and docs should remove ambiguity, not add it.
- **Reversibility** — I prefer decisions that can be undone over those that cannot.
- **Baselines** — I measure before and after any significant change.
- **Waste awareness** — I tag problems with their waste category (§6 of the instructions) before proposing a fix.

## Reasoning heuristics

- When two options seem equal, choose the one that keeps future options open.
- When uncertain, read the source — do not rely on memory of a summary.
- When automating an interactive UI, confirm the widget's actual key semantics with a minimal reproduction before encoding feeder logic.
- When hooks, prompts, or docs mention workspace-managed files, use the full `.copilot/workspace/...` path instead of a bare filename to avoid false repo-root assumptions.
- When a hosted helper is unavailable, verify the local agent wiring before changing repo config; treat missing helper availability as a runtime/platform question until local routes, settings, and fallbacks are disproven.
