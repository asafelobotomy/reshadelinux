# purpose:  Save critical workspace context before conversation compaction
# when:     PreCompact hook — fires when context is about to be truncated
# inputs:   JSON via stdin with trigger field
# outputs:  JSON with additionalContext summarising saved state
# risk:     safe
# ESCALATION: none

$ErrorActionPreference = 'SilentlyContinue'
$inputJson = $input | Out-String
$summaryLines = @()

function Get-PythonCommand {
    foreach ($candidate in @('python3', 'python', 'py')) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) {
            return $candidate
        }
    }
    return $null
}

function Get-ClockSummary {
    $statePath = '.copilot/workspace/runtime/state.json'
    $eventsPath = '.copilot/workspace/runtime/.heartbeat-events.jsonl'
    if (-not (Test-Path $statePath) -and -not (Test-Path $eventsPath)) {
        return ''
    }

    $pythonCommand = Get-PythonCommand
    if ($null -eq $pythonCommand) {
        return ''
    }

    $helperPath = Join-Path $PSScriptRoot 'heartbeat_clock_summary.py'
    if (-not (Test-Path $helperPath)) {
        return ''
    }

    if ($pythonCommand -eq 'py') {
        $output = & py -3 $helperPath 2>$null
        if (-not $output) {
            $output = & py $helperPath 2>$null
        }
    } else {
        $output = & $pythonCommand $helperPath 2>$null
    }

    return ($output | Out-String).Trim()
}

function Get-TriggerLabel {
    param([string]$InputJson)

    if (-not $InputJson.Trim()) {
        return ''
    }

    try {
        $payload = $InputJson | ConvertFrom-Json
        if ($payload.trigger -is [string]) {
            return $payload.trigger.Trim()
        }
    } catch {}

    return ''
}

function Get-MemorySummary {
    if (-not (Test-Path '.copilot/workspace/knowledge/MEMORY.md')) {
        return ''
    }

    $lines = @(Get-Content '.copilot/workspace/knowledge/MEMORY.md' -ErrorAction SilentlyContinue)
    $entries = @()
    $currentSection = ''

    for ($index = 0; $index -lt $lines.Count; ) {
        $trimmed = $lines[$index].Trim()

        if ($trimmed.StartsWith('## ')) {
            $currentSection = $trimmed.Substring(3).Trim()
            $index += 1
            continue
        }

        if ($currentSection -and $trimmed.StartsWith('|')) {
            $block = @()
            while ($index -lt $lines.Count -and $lines[$index].TrimStart().StartsWith('|')) {
                $block += $lines[$index].Trim()
                $index += 1
            }

            if ($block.Count -ge 3) {
                $rows = @()
                foreach ($row in $block[2..($block.Count - 1)]) {
                    $cells = @($row.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
                    $meaningful = @($cells | Where-Object { $_ -and $_ -ne '*(to be discovered)*' })
                    if ($meaningful.Count -gt 0) {
                        $rows += ,@($cells)
                    }
                }

                if ($rows.Count -gt 0) {
                    $preview = (@($rows[-1] | Where-Object { $_ }) -join ' | ')
                    if ($preview.Length -gt 160) {
                        $preview = $preview.Substring(0, 160)
                    }
                    $entries += "${currentSection}: $preview"
                }
            }

            continue
        }

        $index += 1
    }

    if (-not $entries) {
        $fallback = @()
        foreach ($line in $lines) {
            $trimmed = $line.Trim()
            if (-not $trimmed) {
                continue
            }
            if ($trimmed.StartsWith('#') -or $trimmed.StartsWith('|') -or $trimmed.StartsWith('<!--') -or $trimmed.StartsWith('*(')) {
                continue
            }
            if ($trimmed -match '^[\-\|\s]+$') {
                continue
            }
            if ($trimmed.StartsWith('- ')) {
                $trimmed = $trimmed.Substring(2).Trim()
            }
            if ($trimmed -notmatch ':' -and -not $line.TrimStart().StartsWith('- ')) {
                continue
            }
            $fallback += $trimmed
        }

        if ($fallback.Count -gt 0) {
            $entries = @($fallback | Select-Object -Last 3)
        }
    }

    $summary = (@($entries | Select-Object -First 3) -join ' || ')
    if ($summary.Length -gt 500) {
        $summary = $summary.Substring(0, 500)
    }
    return $summary
}

function Get-SoulSummary {
    if (-not (Test-Path '.copilot/workspace/identity/SOUL.md')) {
        return ''
    }

    $lines = @(Get-Content '.copilot/workspace/identity/SOUL.md' -ErrorAction SilentlyContinue)
    $entries = @($lines | ForEach-Object { $_.Trim() } | Where-Object { $_.StartsWith('- ') } | ForEach-Object { $_.Substring(2).Trim() })

    if (-not $entries) {
        $entries = @(
            $lines | ForEach-Object { $_.Trim() } | Where-Object {
                $_ -and -not $_.StartsWith('#') -and -not $_.StartsWith('<!--') -and -not $_.StartsWith('*(')
            } | Select-Object -First 3
        )
    }

    $summary = (@($entries | Select-Object -First 5) -join ' || ')
    if ($summary.Length -gt 400) {
        $summary = $summary.Substring(0, 400)
    }
    return $summary
}

function Add-SummaryLine {
    param(
        [string]$Label,
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $script:summaryLines += "- ${Label}: $Value"
    }
}

$trigger = Get-TriggerLabel -InputJson $inputJson
Add-SummaryLine -Label 'Trigger' -Value $trigger

# Heartbeat pulse
if (Test-Path '.copilot/workspace/operations/HEARTBEAT.md') {
    $pulse = (Select-String -Path '.copilot/workspace/operations/HEARTBEAT.md' -Pattern 'HEARTBEAT' |
              Select-Object -First 1).Line
    Add-SummaryLine -Label 'Heartbeat' -Value $pulse
}

$clockSummary = Get-ClockSummary
Add-SummaryLine -Label 'Clock' -Value $clockSummary

$memorySummary = Get-MemorySummary
Add-SummaryLine -Label 'Memory entries' -Value $memorySummary

$soulSummary = Get-SoulSummary
Add-SummaryLine -Label 'SOUL cues' -Value $soulSummary

# Git status snapshot
try {
    $gitStatus = & git status --porcelain 2>$null | Select-Object -First 10
    if ($gitStatus) {
        $modifiedCount = ($gitStatus | Measure-Object).Count
        Add-SummaryLine -Label 'Git' -Value "$modifiedCount modified files"
    }
} catch {}

if ($summaryLines.Count -eq 0) {
    '{"continue": true}'
    exit 0
}

if ($summaryLines) {
    $summary = "Pre-compaction workspace snapshot:`n" + ($summaryLines -join "`n")
    if ($summary.Length -gt 2000) { $summary = $summary.Substring(0,2000) }

    [PSCustomObject]@{
        hookSpecificOutput = [PSCustomObject]@{
            hookEventName     = 'PreCompact'
            additionalContext = $summary
        }
    } | ConvertTo-Json -Depth 5
} else {
    '{"continue": true}'
}
