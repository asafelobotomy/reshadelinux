#!/usr/bin/env bash
# purpose:  Cross-distro uvx launcher for MCP stdio servers
# when:     Referenced from .vscode/mcp.json "command" field
# inputs:   All arguments are forwarded to uvx (e.g. mcp-server-git --repository .)
# outputs:  Execs into the real uvx process; no stdout of its own
# risk:     safe — read-only binary probe, then exec
set -euo pipefail

# Allow explicit override via environment variable
if [[ -n "${UVX_BIN:-}" ]] && [[ -x "$UVX_BIN" ]]; then
  exec "$UVX_BIN" "$@"
fi

# Probe standard locations (covers Ubuntu, Arch, Fedora, pipx, Homebrew)
for candidate in \
  "$(command -v uvx 2>/dev/null || true)" \
  "$HOME/.local/bin/uvx" \
  "$HOME/.cargo/bin/uvx" \
  "/opt/homebrew/bin/uvx" \
  "/home/linuxbrew/.linuxbrew/bin/uvx" \
  "$HOME/.linuxbrew/bin/uvx" \
  "/usr/local/bin/uvx" \
  "/usr/bin/uvx"; do
  [[ -n "$candidate" ]] && [[ -x "$candidate" ]] && exec "$candidate" "$@"
done

# Toolbox / Distrobox fallback (Bazzite / immutable Fedora Atomic desktops)
if command -v distrobox &>/dev/null; then
  exec distrobox enter -- uvx "$@" 2>/dev/null
elif command -v toolbox &>/dev/null; then
  exec toolbox run uvx "$@" 2>/dev/null
fi

echo "ERROR: uvx not found." >&2
echo "Install uv: https://docs.astral.sh/uv/getting-started/installation/" >&2
echo "Override: export UVX_BIN=/path/to/uvx" >&2
exit 1
