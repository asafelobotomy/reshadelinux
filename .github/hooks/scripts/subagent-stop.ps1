# purpose:  Log subagent completion and write diary entry if durable findings exist
# when:     SubagentStop hook — fires after a subagent finishes
# inputs:   JSON via stdin with subagent result details
# outputs:  JSON with additionalContext summarising outcome
# risk:     safe — creates/appends diary files only
# ESCALATION: none

$ErrorActionPreference = 'Stop'

$input_json = [Console]::In.ReadToEnd()
$agentName = 'unknown'
$result = ''
try {
  $payload = $input_json | ConvertFrom-Json -ErrorAction Stop
  if ($null -ne $payload.agentName -and [string]::IsNullOrWhiteSpace([string]$payload.agentName) -eq $false) {
    $agentName = [string]$payload.agentName
  }
  if ($null -ne $payload.result) {
    $result = ([string]$payload.result)
    if ($result.Length -gt 200) {
      $result = $result.Substring(0, 200)
    }
  }
}
catch {
  $payload = $null
}

$agentLower = $agentName.ToLowerInvariant()
$diaryDir = '.copilot/workspace/knowledge/diaries'
$diaryFile = Join-Path $diaryDir "${agentLower}.md"

if ([string]::IsNullOrWhiteSpace($result) -eq $false) {
  $shouldWrite = $true
  if (Test-Path $diaryFile) {
    $shouldWrite = -not (Select-String -Path $diaryFile -SimpleMatch -Quiet -Pattern $result)
  }

  if ($shouldWrite) {
    New-Item -ItemType Directory -Path $diaryDir -Force | Out-Null
    if (-not (Test-Path $diaryFile)) {
      [System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $diaryDir).Path + [System.IO.Path]::DirectorySeparatorChar + "${agentLower}.md", "# ${agentName} Diary`n`n")
    }

    $timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Add-Content -Path $diaryFile -Value "- ${timestamp} ${result}"

    $lines = Get-Content $diaryFile
    if ($lines.Count -gt 30) {
      $keptLines = @($lines[0], $lines[1]) + @($lines | Select-Object -Last 28)
      Set-Content -Path $diaryFile -Value $keptLines
    }
  }
}

$context = "Subagent ${agentName} completed. Review results before continuing."

$output = [ordered]@{
  hookSpecificOutput = [ordered]@{
    hookEventName = 'SubagentStop'
    additionalContext = $context
  }
}

$output | ConvertTo-Json -Compress
