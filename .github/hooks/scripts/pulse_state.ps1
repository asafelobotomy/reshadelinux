function Get-DefaultPolicy {
    [ordered]@{
        retrospective = [ordered]@{
            thresholds = [ordered]@{
                modified_files = [ordered]@{
                    supporting = 5
                    strong = 8
                }
                elapsed_minutes = [ordered]@{
                    supporting = 15
                    strong = 30
                }
                idle_gap_minutes = 10
            }
            health_digest = [ordered]@{
                min_emit_spacing_seconds = 120
            }
            messages = [ordered]@{
                session_start_guidance = 'Open .copilot/workspace/operations/HEARTBEAT.md and run the Checks section. If the Stop hook later flags significant work, call the session_reflect MCP tool before stopping.'
                explicit_system = 'Heartbeat trigger detected. Run .copilot/workspace/operations/HEARTBEAT.md checks now.'
                stop_reflect_instruction = 'Significant session detected. Call the session_reflect MCP tool now, process its output silently, then stop normally. If the MCP tool is unavailable, briefly review: execution accuracy, scope completeness, and anything worth persisting to .copilot/workspace/identity/SOUL.md, .copilot/workspace/knowledge/MEMORY.md, and .copilot/workspace/knowledge/USER.md, then rerun session_reflect once the heartbeat MCP server is restored.'
                accepted_reason = 'The user requested a retrospective. Call the session_reflect MCP tool, process its output, persist insights, then stop normally.'
            }
        }
    }
}

function Get-Policy {
    if (Test-Path $policyPath) {
        try {
            $loaded = Get-Content $policyPath -Raw | ConvertFrom-Json -AsHashtable
            if ($null -ne $loaded) {
                return $loaded
            }
        } catch {}
    }
    return Get-DefaultPolicy
}

function Get-DefaultState {
    [ordered]@{
        schema_version = 1
        session_id = 'unknown'
        session_state = 'pending'
        retrospective_state = 'idle'
        last_trigger = ''
        last_write_epoch = 0
        last_soft_trigger_epoch = 0
        last_compaction_epoch = 0
        last_explicit_epoch = 0
        session_start_epoch = 0
        session_start_git_count = 0
        task_window_start_epoch = 0
        last_raw_tool_epoch = 0
        active_work_seconds = 0
        copilot_edit_count = 0
        tool_call_counter = 0
        intent_phase = 'quiet'
        intent_phase_epoch = 0
        intent_phase_version = 1
        last_digest_key = ''
        last_digest_epoch = 0
        digest_emit_count = 0
        overlay_sensitive_surface = $false
        overlay_parity_required = $false
        overlay_verification_expected = $false
        overlay_decision_capture_needed = $false
        overlay_retro_requested = $false
        signal_edit_started = $false
        signal_scope_supporting = $false
        signal_scope_strong = $false
        signal_work_supporting = $false
        signal_work_strong = $false
        signal_compaction_seen = $false
        signal_idle_reset_seen = $false
        signal_cross_cutting = $false
        signal_scope_widening = $false
        signal_reflection_likely = $false
        route_candidate = ''
        route_reason = ''
        route_confidence = 0.0
        route_source = ''
        route_emitted = $false
        route_epoch = 0
        route_last_hint_epoch = 0
        route_emitted_agents = @()
        route_signal_counts = [ordered]@{}
        changed_path_families = @()
        touched_files_sample = @()
        unique_touched_file_count = 0
        prior_small_batches = $false
        prior_explicitness = $false
        prior_reversibility = $false
        prior_baseline_sensitive = $false
        prior_research_first = $false
        prior_non_interruptive_ux = $false
    }
}

function Get-State {
    $state = Get-DefaultState
    if (Test-Path $statePath) {
        try {
            $loaded = Get-Content $statePath -Raw | ConvertFrom-Json
            foreach ($key in @($state.Keys)) {
                $property = $loaded.PSObject.Properties[$key]
                if ($null -ne $property) {
                    $state[$key] = $property.Value
                }
            }
        } catch {}
    }
    return $state
}

function Save-State([hashtable]$State) {
    if (-not (Test-Path $workspace)) { return }
    $tmp = "$statePath.tmp"
    ($State | ConvertTo-Json -Depth 8) + "`n" | Set-Content $tmp -Encoding utf8 -NoNewline
    Move-Item -Force $tmp $statePath
}

function Convert-EpochToUtcString([int64]$Epoch) {
    [DateTimeOffset]::FromUnixTimeSeconds($Epoch).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Add-HeartbeatEvent([string]$Name, [string]$Detail = '', [nullable[int]]$DurationS = $null) {
    if (-not (Test-Path $workspace)) { return }
    $record = [ordered]@{ ts = $now; ts_utc = (Convert-EpochToUtcString $now); trigger = $Name }
    if ($Detail) { $record.detail = $Detail }
    if ($null -ne $DurationS) { $record.duration_s = $DurationS }
    if ($sessionId) { $record.session_id = [string]$sessionId }
    $payload = ($record | ConvertTo-Json -Depth 4 -Compress) + "`n"
    $parent = Split-Path -Parent $eventsPath
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $payload | Add-Content $eventsPath -Encoding utf8
}

function Get-SessionMedians {
    $durations = @()
    if (-not (Test-Path $eventsPath)) { return '' }
    try {
        foreach ($line in (Get-Content $eventsPath -Encoding utf8)) {
            if (-not $line.Trim()) { continue }
            try {
                $parsedStop = $line | ConvertFrom-Json
                if ($parsedStop.trigger -eq 'stop' -and $null -ne $parsedStop.duration_s) {
                    $durations += [int]$parsedStop.duration_s
                }
            } catch {}
        }
    } catch { return '' }
    if ($durations.Count -eq 0) { return '' }
    $sorted = $durations | Sort-Object
    $count = $sorted.Count
    $mid = [int]($count / 2)
    $median = if ($count % 2 -eq 0) {
        [int](($sorted[$mid - 1] + $sorted[$mid]) / 2)
    } else {
        $sorted[$mid]
    }
    $mins = [int]($median / 60)
    $secs = $median % 60
    $label = if ($mins -ge 1) {
        if ($secs -lt 30) { "~${mins}m" } else { "~$($mins + 1)m" }
    } else {
        "~${secs}s"
    }
    return "Typical session: $label (median of $count)."
}

function Invoke-PruneEvents([int]$Keep = 100) {
    if (-not (Test-Path $eventsPath)) { return }
    try {
        $lines = @(Get-Content $eventsPath -Encoding utf8 | Where-Object { $_.Trim() })
        if ($lines.Count -gt $Keep) {
            $start = $lines.Count - $Keep
            ($lines[$start..($lines.Count - 1)] -join "`n") + "`n" | Set-Content $eventsPath -Encoding utf8 -NoNewline
        }
    } catch {}
}

function Set-Sentinel([string]$SessionId, [string]$Status) {
    if (-not (Test-Path $workspace)) { return }
    $ts = Convert-EpochToUtcString $now
    $payload = "$SessionId|$ts|$Status"
    $parent = Split-Path -Parent $sentinelPath
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $payload | Set-Content $sentinelPath -Encoding utf8 -NoNewline
}

function Test-SentinelComplete {
    if (-not (Test-Path $sentinelPath)) { return $false }
    try {
        $line = (Get-Content $sentinelPath -Raw).Trim()
        $parts = $line -split '\|'
        if ($parts.Count -ge 3 -and $parts[2] -eq 'complete') {
            return $true
        }
    } catch {}
    return $false
}

function Test-ReflectionComplete([string]$SessionId, [int64]$SessionStartEpoch) {
    if (-not (Test-Path $eventsPath)) { return $false }
    try {
        $lines = @(Get-Content $eventsPath -Encoding utf8)
    } catch {
        return $false
    }
    for ($index = $lines.Count - 1; $index -ge 0; $index--) {
        $line = [string]$lines[$index]
        if (-not $line.Trim()) { continue }
        try {
            $parsed = $line | ConvertFrom-Json
        } catch {
            continue
        }
        if ($parsed.trigger -ne 'session_reflect' -or $parsed.detail -ne 'complete') {
            continue
        }
        $reflectSessionId = [string]($parsed.session_id ?? '')
        if ($reflectSessionId) {
            return $reflectSessionId -eq $SessionId
        }
        $reflectTs = $parsed.ts
        if ($SessionStartEpoch -gt 0 -and $null -ne $reflectTs) {
            return [int64]$reflectTs -ge $SessionStartEpoch
        }
    }
    return $false
}

function Test-HeartbeatFresh([int]$Minutes) {
    if (-not (Test-Path $heartbeatPath)) { return $false }
    try {
        $mtime = (Get-Item $heartbeatPath).LastWriteTimeUtc
        return ((Get-Date).ToUniversalTime() - $mtime -lt [TimeSpan]::FromMinutes($Minutes))
    } catch {
        return $false
    }
}

function Get-GitModifiedFileCount {
    try {
        $statusLines = @(& git status --porcelain 2>$null | Where-Object { $_.Trim() })
        return $statusLines.Count
    } catch {
        return 0
    }
}

function Read-WorkspaceFile([string]$Name, [int]$Limit = 4000) {
    $path = Join-Path $workspace $Name
    if (-not (Test-Path $path)) { return '' }
    try {
        $text = [string](Get-Content $path -Raw -Encoding utf8)
        if ($text.Length -gt $Limit) {
            return $text.Substring(0, $Limit)
        }
        return $text
    } catch {
        return ''
    }
}

function Get-SessionPriors {
    $soul = ([string](Read-WorkspaceFile 'identity/SOUL.md')).ToLowerInvariant()
    $user = ([string](Read-WorkspaceFile 'knowledge/USER.md')).ToLowerInvariant()
    return [ordered]@{
        prior_small_batches = $soul.Contains('small batches')
        prior_explicitness = $soul.Contains('explicit over implicit')
        prior_reversibility = $soul.Contains('reversibility')
        prior_baseline_sensitive = $soul.Contains('baselines')
        prior_research_first = ($user.Contains('research and design confirmation') -or $user.Contains('investigation preference'))
        prior_non_interruptive_ux = ($user.Contains('dislikes disruptive') -or $user.Contains('non-blocking'))
    }
}

function Get-RetrospectiveState([hashtable]$State) {
    if ($State['retrospective_state']) { return [string]$State['retrospective_state'] }
    return 'idle'
}

function Test-RetrospectiveRequest([string]$Prompt) {
    if ($Prompt -notmatch '(?i)\bretrospective\b') { return $false }
    if ($Prompt -match "(?i)\b(no|skip|don't|do not|not now)\b.*\bretrospective\b") { return $false }
    if ($Prompt -match '(?i)\b(explain|review|describe|summari[sz]e|discuss|compare|analy[sz]e|policy|threshold|logic|docs?|documentation|rules?)\b') { return $false }
    return (
        $Prompt -match '(?i)^\s*retrospective(?:\s+(?:now|please))?\s*[?.!]*$' -or
        $Prompt -match '(?i)^\s*(run|do|start|perform)\s+(a\s+)?retrospective\b' -or
        $Prompt -match '(?i)\b(run|do|start|perform)\b.*\bretrospective\b' -or
        $Prompt -match '(?i)\b(can|could|would)\s+you\b.*\b(run|do|start|perform)\b.*\bretrospective\b' -or
        $Prompt -match '(?i)\bplease\b.*\b(run|do|start|perform)\b.*\bretrospective\b'
    )
}

function Test-HeartbeatRequest([string]$Prompt) {
    if ($Prompt -match "(?i)\b(no|skip|don't|do not)\b.*\b(heartbeat|health check)\b") { return $false }
    if ($Prompt -match '(?i)\b(explain|review|describe|summari[sz]e|discuss|compare|analy[sz]e|policy|threshold|logic|docs?|documentation|rules?)\b') { return $false }
    return (
        $Prompt -match '(?i)^\s*heartbeat(?:\s+now)?\s*[?.!]*$' -or
        $Prompt -match '(?i)^\s*(check|run)\s+(your\s+)?heartbeat\b' -or
        $Prompt -match '(?i)\b(check|run)\b.*\bheartbeat\b' -or
        $Prompt -match '(?i)\b(run|do)\b.*\bhealth check\b' -or
        $Prompt -match '(?i)\b(can|could|would)\s+you\b.*\b(check|run|do)\b.*\b(heartbeat|health check)\b'
    )
}

function Close-WorkWindow([hashtable]$State) {
    $taskWindowStart = [int64]($State['task_window_start_epoch'] ?? 0)
    $lastTool = [int64]($State['last_raw_tool_epoch'] ?? 0)
    if ($taskWindowStart -gt 0 -and $lastTool -ge $taskWindowStart) {
        $windowS = [Math]::Max(0, $lastTool - $taskWindowStart)
        $State['active_work_seconds'] = [int]($State['active_work_seconds'] ?? 0) + $windowS
        $State['task_window_start_epoch'] = 0
    }
    return $State
}

function Get-RetrospectiveRecommendation([hashtable]$State) {
    $strongSignals = New-Object System.Collections.Generic.List[string]
    $supportingSignals = New-Object System.Collections.Generic.List[string]
    $basisSignals = New-Object System.Collections.Generic.List[string]
    $strongModified = [int]($retroModifiedThresholds['strong'] ?? 8)
    $supportingModified = [int]($retroModifiedThresholds['supporting'] ?? 5)
    $strongElapsedMinutes = [int]($retroElapsedThresholds['strong'] ?? 30)
    $supportingElapsedMinutes = [int]($retroElapsedThresholds['supporting'] ?? 15)

    $touchedFiles = [int]($State['unique_touched_file_count'] ?? 0)
    $sessionStartCount = [int]($State['session_start_git_count'] ?? 0)
    $currentCount = Get-GitModifiedFileCount
    $deltaFiles = [Math]::Max(0, $currentCount - $sessionStartCount)
    $editCount = [int]($State['copilot_edit_count'] ?? 0)
    $effectiveFiles = if ($touchedFiles -gt 0) { $touchedFiles } elseif ($deltaFiles -gt 0) { $deltaFiles } else { $editCount }

    if ($effectiveFiles -eq 0) {
        return [ordered]@{ required = $false; basis = 'no file activity detected since session start' }
    }

    $fileLabel = if ($touchedFiles -gt 0) { 'files touched in this session' } elseif ($deltaFiles -gt 0) { 'files changed since session start' } else { 'files edited in this session (previously committed)' }
    if ($effectiveFiles -ge $strongModified) {
        $strongSignals.Add("$effectiveFiles $fileLabel")
    } elseif ($effectiveFiles -ge $supportingModified) {
        $supportingSignals.Add("$effectiveFiles $fileLabel")
    }

    $activeS = [int]($State['active_work_seconds'] ?? 0)
    $activeMinutes = [int]($activeS / 60)
    if ($activeMinutes -ge $strongElapsedMinutes) {
        $strongSignals.Add("${activeMinutes}m active work")
    } elseif ($activeMinutes -ge $supportingElapsedMinutes) {
        $supportingSignals.Add("${activeMinutes}m active work")
    }

    $startEpoch = [int64]($State['session_start_epoch'] ?? 0)
    $lastCompaction = [int64]($State['last_compaction_epoch'] ?? 0)
    if ($startEpoch -gt 0 -and $lastCompaction -ge $startEpoch) {
        $supportingSignals.Add('context compaction occurred')
    }

    foreach ($signal in $strongSignals) {
        $basisSignals.Add($signal)
    }
    foreach ($signal in $supportingSignals) {
        $basisSignals.Add($signal)
    }

    return [ordered]@{
        required = ($strongSignals.Count -gt 0 -or $supportingSignals.Count -ge 2)
        basis = ($basisSignals -join ', ')
    }
}
