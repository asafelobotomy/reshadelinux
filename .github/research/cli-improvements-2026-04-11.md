# Research: CLI Improvement Opportunities for reshade-steam

> Date: 2026-04-11 | Agent: Researcher | Status: final

## Summary

Cross-referencing three primary sources — the Command Line Interface Guidelines (clig.dev), GNU Coding Standards §4.8, and the 12 Factor CLI Apps article (Heroku/Jeff Dickey) — against the current reshade-steam CLI surface reveals seven practical improvement opportunities. All fit the Bash project without new dependencies. The codebase is already stronger than most shell scripts in several areas (flag validation, stderr separation for errors, XDG-compliant `MAIN_PATH`), but has clear gaps in color-output hygiene, scripting-friendly quiet/dry-run modes, and exit code taxonomy.

## Sources

| URL | Relevance |
|-----|-----------|
| https://clig.dev | Primary: output, flags, errors, interactivity, env-var, naming sections |
| https://www.gnu.org/prep/standards/html_node/Command_002dLine-Interfaces.html | Primary: long-option pairing, --version, --help mandate |
| https://medium.com/@jdxcode/12-factor-cli-apps-dd3c227a0e46 | Primary: stream discipline, NO_COLOR, XDG, exit codes, speedy startups |
| https://no-color.org | Primary: NO_COLOR env-var standard |

---

## Findings

### 1 — NO_COLOR / TTY-aware ANSI stripping  
**Status: missing entirely** | **Effort: quick win**

`lib/logging.sh` sets `_RED`, `_CYN`, `_B`, `_R` colour constants unconditionally and emits them in every `printStep` and `printErr` call. There is no check against `$NO_COLOR`, `$TERM=dumb`, or whether stderr/stdout is a TTY.

The TTY variable `_has_tty` is computed in `lib/config.sh` (line 4–5) but is used only for UI-backend selection; it never reaches the logging layer. Consequently, piping `--update-all` output to a log file embeds raw ANSI escape codes, breaking grep, diff, and CI log renderers.

**Sources:** clig.dev (Output / Environment variables), no-color.org, 12-factor CLI (Factor 6)  
**Recommendation:** In `logging.sh` initialisation, strip colour constants when `${NO_COLOR+x}` is set, `$TERM == dumb`, or stderr is not a TTY (`[[ ! -t 2 ]]`). A `--no-color` flag (or `RESHADE_NO_COLOR=1` env var) should also disable them. Zero external dependencies.

---

### 2 — `--quiet / -q`: suppress non-essential output for scripts  
**Status: missing entirely** | **Effort: quick win → medium**

There is no way to silence `printStep` messages during scripted runs. When `--update-all` is embedded in a batch script or CI pipeline, the operator gets every step header regardless.

CLIG (Arguments and flags): *"provide a `-q` option to suppress all non-essential output — [to] avoid clumsy redirection of stderr to /dev/null"*.

**Sources:** clig.dev (Output, Arguments and flags)  
**Recommendation:** Add `--quiet/-q` to `parseCliArgs`; set a `CLI_QUIET=1` global. Guard `printStep` with `[[ ${CLI_QUIET:-0} -eq 0 ]]`. `printErr` stays unconditional. This is a quick addition to `cli.sh` and `logging.sh` with no flow changes.

---

### 3 — `--dry-run / -n`: preview without mutating state  
**Status: missing entirely** | **Effort: larger change**

The script downloads files, creates symlinks inside Wine prefixes, writes state files under `~/.local/share/reshade`, and modifies `WINEDLLOVERRIDES`. None of these mutations are previewed before execution.

CLIG (Arguments and Flags): *"`-n, --dry-run` — Do not run the command, but describe the changes that would occur. For example, rsync, git add."* Specifically flagged as recommended for operations that are "a bigger local change… complex bulk modification that can't be easily undone."

This is directly applicable to `--update-all` (potentially touching many Wine prefixes) and to first installs (downloading ~MB of ReShade + shaders before the user has approved the targets).

**Sources:** clig.dev (Arguments and flags, Robustness)  
**Recommendation:** Add `--dry-run/-n`; thread a `DRY_RUN=1` guard into the installation, symlink, and state-write paths in `lib/install.sh` and `lib/shaders.sh`. Print "would do X" instead of executing. This is the largest item here but has high value for automated testing of the batch-update path.

---

### 4 — Machine-readable output for list commands (`--json`)  
**Status: missing entirely** | **Effort: quick win**

`--list-shader-repos` currently emits tab-aligned text:
```
sweetfx-shaders   SweetFX by CeeJayDK | ...
```
There is no way for a script to reliably parse this (tab width varies; labels contain arbitrary text). CLIG: *"Display output as formatted JSON if `--json` is passed. jq is a common tool for working with JSON on the command-line."* The 12-factor article (Factor 8) recommends JSON or CSV as machine-readable alternates for table output.

For reshade-steam specifically, a JSON output for `--list-shader-repos` would let wrapper scripts (e.g., a Gamescope integration) introspect available repos and construct `--shader-repos=` arguments programmatically.

**Sources:** clig.dev (Output), 12-factor CLI (Factor 8)  
**Recommendation:** Add `--json` flag; when combined with `--list-shader-repos`, emit a JSON array of `{"name":"…","uri":"…","description":"…"}` objects. This is entirely self-contained in `lib/cli.sh` / `printAvailableShaderRepos`. Tool needed: none beyond bash's built-in printf.

---

### 5 — Help text: add examples and a support URL  
**Status: worth enhancing** | **Effort: quick win**

`printUsage()` is a flat, uncommented list of flags — no usage examples, no section headers, no issue-tracker URL. CLIG (Help): *"Lead with examples… Provide a support path for feedback and issues. A website or GitHub link in the top-level help text is common."* 12-factor CLI Factor 1 echoes this: the most-referenced documentation is common-usage examples.

Compared tools like `rsync`, `git`, `curl`, and `jq` all show at minimum one or two examples before the options block.

**Sources:** clig.dev (Help), 12-factor CLI (Factor 1)  
**Recommendation:** Add an "Examples:" block above the flags list in `printUsage()` showing 3–4 representative invocations (interactive, scripted `--cli`, batch `--update-all`, `--list-shader-repos`). Append a GitHub issues URL. No functional change — purely a text edit in `lib/cli.sh`.

---

### 6 — Explicit `--no-input` for strict non-interactive use  
**Status: missing entirely** | **Effort: medium**

`--cli` sets `UI_BACKEND=cli`, which disables the yad/whiptail dialogs but still falls through to interactive text prompts when required arguments are absent (game path, DLL selection, etc.). There is no flag that *guarantees* the script will never prompt — it will silently block a CI pipeline waiting for user input.

CLIG (Interactivity): *"If `--no-input` is passed, don't prompt or do anything interactive. This allows users an explicit way to disable all prompts. If the command requires input, fail and tell the user how to pass the information as a flag."*

**Sources:** clig.dev (Interactivity)  
**Recommendation:** Add `--no-input`; when set, any code path that would call a prompt function (readline, `read`, UI widgets) should instead call `printErr` with the missing flag name. This requires auditing the interactive prompts in `lib/game_selection.sh` and `lib/flow.sh` — medium work, but the resulting contract is invaluable for scripting and CI.

---

### 7 — Exit code taxonomy (currently only 0 / 1)  
**Status: worth enhancing** | **Effort: medium**

All errors route through `printErr` → `exit 1`. Callers (scripts, CI steps) cannot distinguish between: bad user argument (re-run with different flag), network failure (retry later), prerequisite missing (install curl), or installation failure (inspect log). CLIG (The Basics): *"Return zero exit code on success, non-zero on failure. Map the non-zero exit codes to the most important failure modes."* 12-factor CLI Factor 5 also recommends error messages include a "how to fix" component, implying differentiated error classes.

Comparable tools: `apt-get` uses exit 100 for command-not-found, `curl` has ~30 documented exit codes, `rsync` distinguishes protocol errors from I/O errors.

**Sources:** clig.dev (The Basics), 12-factor CLI (Factor 5)  
**Recommendation:** Define a small set of named exit codes (e.g., 1 = usage/argument error, 2 = prerequisite/dependency missing, 3 = network/download failure, 4 = filesystem/permission error). Add a `die_with_code <code> <message>` variant alongside `printErr`. Document in README. This is a medium refactor of `logging.sh` and all `printErr` call sites.

---

## Prioritised Shortlist

| # | Opportunity | Effort | Status |
|---|-------------|--------|--------|
| 1 | NO_COLOR / TTY-aware colour stripping in logging.sh | Quick win | Missing entirely |
| 4 | `--json` for `--list-shader-repos` | Quick win | Missing entirely |
| 5 | Help text: examples + GitHub URL | Quick win | Worth enhancing |
| 2 | `--quiet / -q` flag | Quick win → Medium | Missing entirely |
| 6 | `--no-input` strict non-interactive mode | Medium | Missing entirely |
| 7 | Exit code taxonomy (≥3 distinct codes) | Medium | Worth enhancing |
| 3 | `--dry-run / -n` | Larger | Missing entirely |

Items 1, 4, and 5 can each be completed in a single focused edit. Items 2 and 6 touch two modules each. Item 7 touches all `printErr` call sites. Item 3 requires threading a guard through the install flow.

## Gaps / Further research needed

- **Shell completion** — CLIG and 12-factor both recommend tab-completion scripts (bash/zsh). Not researched here; would be a separate task.
- **`--version` diagnostic enrichment** — 12-factor recommends including platform/environment context in version output (e.g., Flatpak vs native, AppImage vs git clone). Not covered in this report.
- **Comparable Proton/Wine tools CLI conventions** — vkBasalt, Protontricks, Heroic, and Bottles were not fetched; their CLI patterns might surface additional domain-specific conventions worth adopting.
