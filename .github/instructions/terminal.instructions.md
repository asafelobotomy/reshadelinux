---
name: Terminal Discipline
applyTo: "**/*.sh,**/*.bash,**/*.zsh,**/*.ps1"
description: "Terminal session safety — shell isolation, strict-mode wrappers, variable naming, and output management"
---

# Terminal Discipline

- For high-volume commands, capture the full output to a log file and print only a bounded tail instead of streaming everything.
- If the repo documents a terminal-safe wrapper for a noisy command, prefer it over the raw command when using terminal tools.
- Prefer repo scripts or bash wrappers over ad hoc shell control flow when a command needs exit-status plumbing, redirection, or retries.
- A single existing command with no shell control flow, tempfile plumbing, redirection, or shell-specific syntax may run directly in the terminal.
- If the repo provides a generic isolated-shell wrapper, use it for ad hoc one-liners or multi-step snippets instead of relying on the persistent terminal's current shell state.
- If the repo provides a stdin or here-doc isolated-shell wrapper, use it for multi-line snippets and shell-specific syntax.
- Never run `set -euo pipefail` or `setopt errexit nounset pipefail` as a standalone terminal command in the persistent zsh session. Shell integration hooks can inherit that global state and terminate the session on the next prompt cycle.
- For ad hoc strict-mode one-liners, prefer a repo wrapper if one exists. Otherwise run the snippet through a child Bash process with strict mode enabled instead of mutating the parent zsh session.
- For multi-line strict-mode snippets, prefer a dedicated stdin or here-doc wrapper when the repo provides one. Otherwise run the snippet through a child Bash process with strict mode enabled instead of mutating the parent zsh session.
- Use shell-specific child wrappers for zsh, `sh`, or PowerShell syntax instead of assuming the persistent terminal is already in the right shell.
- Use `get_terminal_output`, `send_to_terminal`, and `kill_terminal` only with the exact opaque terminal ID returned by `run_in_terminal` async mode.
- Treat `get_terminal_output`, `send_to_terminal`, and `kill_terminal` as valid only when `run_in_terminal` returned a live terminal ID, typically from async mode or from a sync command that outlived its timeout.
- Do not pass shell names, terminal labels, editor terminals, or `execution_subagent` results to `get_terminal_output`, `send_to_terminal`, or `kill_terminal`.
- Use `terminal_last_command` and `terminal_selection` only for the currently active editor terminal. They do not read or control `run_in_terminal` async sessions.
- If you only need command output rather than a persistent background session, prefer a synchronous terminal run or `execution_subagent` over polling a background terminal.
- Reuse async terminals only for genuinely interactive or persistent sessions, and call `kill_terminal` when that session is no longer needed.
- Do not add `sleep` loops or blind polling around background terminals. Check output when the workflow has a reason to produce new output, and inspect the current transcript before sending more input.
- For standard build or run workflows, prefer repo scripts or `create_and_run_task`. Reserve async terminal sessions for cases that truly need a persistent interactive shell.
- In zsh workspaces, avoid reserved variable names such as `status`; use `rc`, `exit_code`, or `command_rc` instead.
- Do not rely on profile files, aliases, or exported shell options for ad hoc snippets. Child wrappers should start from a clean shell state.
- If a failure is caused by shell semantics rather than the underlying command, stop retrying equivalent one-liners and switch to a repo script or simpler direct invocation.
