$phaseOrder = @('quiet', 'orienting', 'focused', 'widening', 'consolidating', 'reflective')
$sensitiveFamilies = @('manifest', 'config', 'hook', 'agent', 'memory', 'ci_release')
$verificationFamilies = @('runtime', 'hook', 'config', 'manifest', 'ci_release')

function Get-ActivityMetrics([hashtable]$State) {
    $baseline = [int]($State['session_start_git_count'] ?? 0)
    $deltaFiles = [Math]::Max(0, (Get-GitModifiedFileCount) - $baseline)
    $editCount = [int]($State['copilot_edit_count'] ?? 0)
    $touchedCount = [int]($State['unique_touched_file_count'] ?? 0)
    $activeS = [int]($State['active_work_seconds'] ?? 0)
    $taskWindowStart = [int64]($State['task_window_start_epoch'] ?? 0)
    $lastTool = [int64]($State['last_raw_tool_epoch'] ?? 0)
    if ($taskWindowStart -gt 0 -and $lastTool -ge $taskWindowStart) {
        $activeS += [Math]::Max(0, $lastTool - $taskWindowStart)
    }
    return [ordered]@{
        delta_files = $deltaFiles
        edit_count = $editCount
        touched_count = $touchedCount
        effective_files = [Math]::Max([Math]::Max($deltaFiles, $editCount), $touchedCount)
        active_seconds = $activeS
        active_minutes = [int]($activeS / 60)
    }
}

function Get-SignalSnapshot([hashtable]$State) {
    $metrics = Get-ActivityMetrics $State
    $strongModified = [int]($retroModifiedThresholds['strong'] ?? 8)
    $supportingModified = [int]($retroModifiedThresholds['supporting'] ?? 5)
    $strongElapsedMinutes = [int]($retroElapsedThresholds['strong'] ?? 30)
    $supportingElapsedMinutes = [int]($retroElapsedThresholds['supporting'] ?? 15)
    $startEpoch = [int64]($State['session_start_epoch'] ?? 0)
    $compactionSeen = ($startEpoch -gt 0 -and [int64]($State['last_compaction_epoch'] ?? 0) -ge $startEpoch)
    $families = @($State['changed_path_families'])
    $retroRecommendation = Get-RetrospectiveRecommendation $State
    return [ordered]@{
        tool_activity = ([int]($State['tool_call_counter'] ?? 0) -gt 0)
        edit_started = ([int]$metrics['effective_files'] -gt 0)
        scope_supporting = ([int]$metrics['effective_files'] -ge $supportingModified -and [int]$metrics['effective_files'] -lt $strongModified)
        scope_strong = ([int]$metrics['effective_files'] -ge $strongModified)
        work_supporting = ([int]$metrics['active_minutes'] -ge $supportingElapsedMinutes -and [int]$metrics['active_minutes'] -lt $strongElapsedMinutes)
        work_strong = ([int]$metrics['active_minutes'] -ge $strongElapsedMinutes)
        compaction_seen = $compactionSeen
        idle_reset_seen = [bool]($State['signal_idle_reset_seen'] ?? $false)
        cross_cutting = (@($families).Count -ge 3)
        scope_widening = ([int]$metrics['effective_files'] -ge 3 -or @($families).Count -ge 2)
        reflection_likely = [bool]$retroRecommendation.required
        delta_files = [int]$metrics['delta_files']
        edit_count = [int]$metrics['edit_count']
        touched_count = [int]$metrics['touched_count']
        effective_files = [int]$metrics['effective_files']
        active_seconds = [int]$metrics['active_seconds']
        active_minutes = [int]$metrics['active_minutes']
    }
}

function Get-Overlays([hashtable]$State, [hashtable]$Signals) {
    $families = @($State['changed_path_families'])
    $paths = @($State['touched_files_sample'])
    $parityRequired = $false
    foreach ($pathText in $paths) {
        if (Test-PathRequiresParity $pathText) {
            $parityRequired = $true
            break
        }
    }
    return [ordered]@{
        overlay_sensitive_surface = (@($families | Where-Object { $sensitiveFamilies -contains $_ }).Count -gt 0)
        overlay_parity_required = $parityRequired
        overlay_verification_expected = (@($families | Where-Object { $verificationFamilies -contains $_ }).Count -gt 0)
        overlay_decision_capture_needed = ([bool]$Signals['compaction_seen'] -or [bool]$Signals['cross_cutting'])
        overlay_retro_requested = ((Get-RetrospectiveState $State) -eq 'accepted')
    }
}

function Get-AdvancedPhase([hashtable]$State, [hashtable]$Signals, [hashtable]$Overlays) {
    $phase = [string]($State['intent_phase'] ?? 'quiet')
    if (-not ($phaseOrder -contains $phase)) { $phase = 'quiet' }
    while ($true) {
        $newPhase = $phase
        if ([bool]$Overlays['overlay_retro_requested'] -or [bool]$Signals['reflection_likely']) {
            $newPhase = 'reflective'
        } elseif ($phase -eq 'quiet') {
            if ([bool]$Signals['edit_started'] -or [bool]$Signals['scope_supporting'] -or [bool]$Signals['scope_strong']) {
                $newPhase = 'focused'
            } elseif ([bool]$Signals['tool_activity']) {
                $newPhase = 'orienting'
            }
        } elseif ($phase -eq 'orienting') {
            if ([bool]$Signals['edit_started']) {
                $newPhase = 'focused'
            }
        } elseif ($phase -eq 'focused') {
            if ([bool]$Signals['scope_widening']) {
                $newPhase = 'widening'
            }
        } elseif ($phase -eq 'widening') {
            if (
                [bool]$Signals['scope_supporting'] -or
                [bool]$Signals['work_supporting'] -or
                [bool]$Signals['work_strong'] -or
                [bool]$Overlays['overlay_verification_expected'] -or
                [bool]$Overlays['overlay_decision_capture_needed'] -or
                [bool]$Overlays['overlay_sensitive_surface']
            ) {
                $newPhase = 'consolidating'
            }
        }
        if ($newPhase -eq $phase) { return $phase }
        $phase = $newPhase
    }
}

function Get-ScopeEvidenceText([hashtable]$Signals) {
    $activeMinutes = [int]($Signals['active_minutes'] ?? 0)
    $deltaFiles = [int]($Signals['delta_files'] ?? 0)
    $touchedCount = [int]($Signals['touched_count'] ?? 0)
    $editCount = [int]($Signals['edit_count'] ?? 0)
    if ($deltaFiles -gt 0) {
        $scope = "$deltaFiles files changed"
    } elseif ($touchedCount -gt 0) {
        $scope = "$touchedCount files touched"
    } else {
        $scope = "$editCount edits tracked"
    }
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add("${activeMinutes}m active")
    $parts.Add($scope)
    if ([bool]$Signals['compaction_seen']) {
        $parts.Add('compaction seen')
    }
    return ($parts -join ', ')
}

function Get-DigestIntent([string]$Phase, [hashtable]$Overlays, [hashtable]$Signals) {
    if ([bool]$Overlays['overlay_retro_requested']) {
        return [ordered]@{ intent = 'retrospective requested'; evidence = 'Prepare reflective closure before stopping' }
    }
    if ($Phase -eq 'reflective') {
        return [ordered]@{
            intent = 'reflection likely at stop'
            evidence = "Significant session signals are active ($(Get-ScopeEvidenceText $Signals))"
        }
    }
    if ([bool]$Overlays['overlay_parity_required']) {
        return [ordered]@{ intent = 'preserve parity'; evidence = 'Mirrored surfaces are now active' }
    }
    if ([bool]$Overlays['overlay_verification_expected']) {
        return [ordered]@{ intent = 'tests and validation likely next'; evidence = 'Validation-sensitive work is accumulating' }
    }
    if ([bool]$Overlays['overlay_decision_capture_needed']) {
        return [ordered]@{ intent = 'capture decisions before loss'; evidence = 'Context compaction or broad work increases loss risk' }
    }
    if ([bool]$Overlays['overlay_sensitive_surface']) {
        return [ordered]@{ intent = 'verify baseline soon'; evidence = 'Sensitive behavior or policy surfaces changed' }
    }
    if ($Phase -eq 'consolidating') {
        return [ordered]@{ intent = 'verify baseline soon'; evidence = "Broader work is accumulating ($(Get-ScopeEvidenceText $Signals))" }
    }
    if ($Phase -eq 'widening') {
        return [ordered]@{ intent = 'capture decision'; evidence = 'Scope widened across multiple surfaces' }
    }
    if ($Phase -eq 'focused') {
        return [ordered]@{ intent = 'keep scope tight'; evidence = 'Narrow implementation work started' }
    }
    if ($Phase -eq 'orienting') {
        return [ordered]@{ intent = 'stay deliberate'; evidence = 'Session context is forming; no meaningful file changes yet' }
    }
    return [ordered]@{ intent = ''; evidence = '' }
}

function Get-ActiveOverlayNames([hashtable]$Overlays) {
    $names = @()
    foreach ($key in @($Overlays.Keys | Sort-Object)) {
        if ([bool]$Overlays[$key]) {
            $names += $key.Replace('overlay_', '')
        }
    }
    return @($names)
}

function Get-DigestKey([string]$Phase, [hashtable]$Overlays, [string]$Intent) {
    if (-not $Intent) { return '' }
    $overlayNames = Get-ActiveOverlayNames $Overlays
    return "$Phase|$Intent|$($overlayNames -join ',')"
}

function Test-ShouldEmitDigest([hashtable]$State, [string]$Phase, [string]$DigestKey, [bool]$PhaseChanged, [bool]$OverlayActivated) {
    if (-not $DigestKey -or $Phase -in @('quiet', 'orienting')) { return $false }
    if ($DigestKey -eq [string]($State['last_digest_key'] ?? '')) { return $false }
    if ($Phase -eq 'focused' -and [bool]($State['prior_non_interruptive_ux'] ?? $false) -and -not $OverlayActivated) {
        return $false
    }
    $lastDigestEpoch = [int]($State['last_digest_epoch'] ?? 0)
    if (
        $lastDigestEpoch -gt 0 -and
        $healthDigestMinSpacingSeconds -gt 0 -and
        ($now - $lastDigestEpoch) -lt $healthDigestMinSpacingSeconds -and
        $Phase -ne 'reflective' -and
        -not $OverlayActivated -and
        -not $PhaseChanged
    ) {
        return $false
    }
    return ($PhaseChanged -or $OverlayActivated -or $DigestKey -ne [string]($State['last_digest_key'] ?? ''))
}

function Format-Digest([string]$Intent, [string]$Evidence) {
    return "Session intent: $Intent. $Evidence."
}

function Update-IntentEngine([hashtable]$State, [object]$Payload = $null, [bool]$Emit = $true) {
    if ($null -ne $Payload) {
        $State = Update-TouchedFiles $State (Get-ToolPaths $Payload)
    }

    $previousPhase = [string]($State['intent_phase'] ?? 'quiet')
    if (-not ($phaseOrder -contains $previousPhase)) { $previousPhase = 'quiet' }

    $signals = Get-SignalSnapshot $State
    $overlays = Get-Overlays $State $signals
    $phase = Get-AdvancedPhase $State $signals $overlays
    $overlayActivated = $false
    foreach ($key in @($overlays.Keys)) {
        if ([bool]$overlays[$key] -and -not [bool]($State[$key] ?? $false)) {
            $overlayActivated = $true
            break
        }
    }
    $phaseChanged = ($phase -ne $previousPhase)

    $State['intent_phase'] = $phase
    if ($phaseChanged -or [int]($State['intent_phase_epoch'] ?? 0) -eq 0) {
        $State['intent_phase_epoch'] = $now
    }
    $State['intent_phase_version'] = 1
    $State['signal_edit_started'] = [bool]$signals['edit_started']
    $State['signal_scope_supporting'] = [bool]$signals['scope_supporting']
    $State['signal_scope_strong'] = [bool]$signals['scope_strong']
    $State['signal_work_supporting'] = [bool]$signals['work_supporting']
    $State['signal_work_strong'] = [bool]$signals['work_strong']
    $State['signal_compaction_seen'] = [bool]$signals['compaction_seen']
    $State['signal_idle_reset_seen'] = [bool]$signals['idle_reset_seen']
    $State['signal_cross_cutting'] = [bool]$signals['cross_cutting']
    $State['signal_scope_widening'] = [bool]$signals['scope_widening']
    $State['signal_reflection_likely'] = [bool]$signals['reflection_likely']
    foreach ($key in @($overlays.Keys)) {
        $State[$key] = [bool]$overlays[$key]
    }

    $digest = $null
    if ($Emit) {
        $digestInfo = Get-DigestIntent $phase $overlays $signals
        $intent = [string]($digestInfo['intent'] ?? '')
        $evidence = [string]($digestInfo['evidence'] ?? '')
        $digestKey = Get-DigestKey $phase $overlays $intent
        if (Test-ShouldEmitDigest $State $phase $digestKey $phaseChanged $overlayActivated) {
            $digest = Format-Digest $intent $evidence
            $State['last_digest_key'] = $digestKey
            $State['last_digest_epoch'] = $now
            $State['digest_emit_count'] = [int]($State['digest_emit_count'] ?? 0) + 1
        }
    }
    return [ordered]@{ state = $State; digest = $digest }
}
