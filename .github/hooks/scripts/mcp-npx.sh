#!/usr/bin/env bash
# purpose:  Cross-distro npx launcher for MCP stdio servers
# when:     Referenced from .vscode/mcp.json "command" field
# inputs:   All arguments are forwarded to npx (e.g. -y @modelcontextprotocol/server-filesystem)
# outputs:  Execs into the real npx process; no stdout of its own
# risk:     safe — read-only binary probe, then exec
set -euo pipefail

# Allow explicit override via environment variable
if [[ -n "${NPX_BIN:-}" ]] && [[ -x "$NPX_BIN" ]]; then
  exec "$NPX_BIN" "$@"
fi

# Probe standard locations (covers Ubuntu, Arch, Fedora, nvm, fnm, Homebrew)
for candidate in \
  "$(command -v npx 2>/dev/null || true)" \
  "$HOME/.local/share/fnm/aliases/default/bin/npx" \
  "$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node/" 2>/dev/null | sort -V | tail -1)/bin/npx" \
  "/opt/homebrew/bin/npx" \
  "/home/linuxbrew/.linuxbrew/bin/npx" \
  "$HOME/.linuxbrew/bin/npx" \
  "/usr/local/bin/npx" \
  "/usr/bin/npx"; do
  [[ -n "$candidate" ]] && [[ -x "$candidate" ]] && exec "$candidate" "$@"
done

# Toolbox / Distrobox fallback (Bazzite / immutable Fedora Atomic desktops)
if command -v distrobox &>/dev/null; then
  exec distrobox enter -- npx "$@" 2>/dev/null
elif command -v toolbox &>/dev/null; then
  exec toolbox run npx "$@" 2>/dev/null
fi

echo "ERROR: npx not found." >&2
echo "Install Node.js: https://nodejs.org/ or via your package manager." >&2
echo "Override: export NPX_BIN=/path/to/npx" >&2
exit 1
