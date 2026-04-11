# purpose:  Inject subagent governance context and diary summary when a subagent is spawned
# when:     SubagentStart hook — fires before a subagent begins work
# inputs:   JSON via stdin with subagent details
# outputs:  JSON with additionalContext including governance + diary summary
# risk:     safe
# ESCALATION: none

$ErrorActionPreference = 'Stop'

$input_json = [Console]::In.ReadToEnd()
$agentName = 'unknown'
try {
  $payload = $input_json | ConvertFrom-Json -ErrorAction Stop
  if ($null -ne $payload.agentName -and [string]::IsNullOrWhiteSpace([string]$payload.agentName) -eq $false) {
    $agentName = [string]$payload.agentName
  }
}
catch {
  $payload = $null
}

$context = "Subagent governance: max depth 3. Inherited protocols: PDCA cycle, Tool Protocol, Skill Protocol. Agent: ${agentName}."

$agentLower = $agentName.ToLowerInvariant()
$diaryFile = Join-Path '.copilot/workspace/knowledge/diaries' "${agentLower}.md"
if (Test-Path $diaryFile) {
  $diaryTail = Get-Content $diaryFile | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 5
  if ($null -ne $diaryTail -and $diaryTail.Count -gt 0) {
    $context = "${context} Recent diary entries: $($diaryTail -join ' ')"
  }
}

$output = [ordered]@{
  hookSpecificOutput = [ordered]@{
    hookEventName = 'SubagentStart'
    additionalContext = $context
  }
}

$output | ConvertTo-Json -Compress
