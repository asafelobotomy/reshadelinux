# purpose:  Orchestrate heartbeat trigger state and retrospective gating.
# when:     Invoked by lifecycle hooks (SessionStart/PostToolUse/PreCompact/Stop/UserPromptSubmit).
# inputs:   JSON on stdin + -Trigger <session_start|pre_tool|soft_post_tool|compaction|stop|user_prompt|explicit>.
# outputs:  JSON hook response (`continue` or Stop `decision:block`).
# risk:     safe
# source:   original
# ESCALATION: none
# STOP LOOP: if stop_hook_active is true in the Stop payload, do not re-enter blocking Stop logic.

[CmdletBinding()]
param(
    [string]$Trigger = ''
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $Trigger) {
    '{"continue": true}'
    exit 0
}

$inputJson = [Console]::In.ReadToEnd()
& (Join-Path $PSScriptRoot 'pulse_runtime.ps1') -Trigger $Trigger -InputJson $inputJson
