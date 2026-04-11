# purpose:  Dispatch PowerShell heartbeat trigger state and retrospective gating.
# when:     Invoked by pulse.ps1 after reading stdin.
# inputs:   -Trigger <session_start|soft_post_tool|compaction|stop|user_prompt|explicit> and raw JSON payload.
# outputs:  JSON hook response (`continue` or Stop `decision:block`).
# risk:     safe

[CmdletBinding()]
param(
    [string]$Trigger = '',
    [string]$InputJson = ''
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not $Trigger) {
    '{"continue": true}'
    exit 0
}

try {
    $payload = if ($InputJson.Trim()) {
        $InputJson | ConvertFrom-Json
    } else {
        [PSCustomObject]@{}
    }
} catch {
    $payload = [PSCustomObject]@{}
}

$workspace = '.copilot/workspace'
$statePath = Join-Path $workspace 'runtime' 'state.json'
$sentinelPath = Join-Path $workspace 'runtime' '.heartbeat-session'
$eventsPath = Join-Path $workspace 'runtime' '.heartbeat-events.jsonl'
$heartbeatPath = Join-Path $workspace 'operations' 'HEARTBEAT.md'
$policyPath = Join-Path $PSScriptRoot 'heartbeat-policy.json'
$routingManifestPath = '.github/agents/routing-manifest.json'
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

. (Join-Path $PSScriptRoot 'pulse_state.ps1')
. (Join-Path $PSScriptRoot 'pulse_paths.ps1')
. (Join-Path $PSScriptRoot 'pulse_intent.ps1')

function Write-JsonOutput([object]$Object) {
    $Object | ConvertTo-Json -Depth 8 -Compress
}

function Get-DefaultRoutingManifest {
    [ordered]@{
        version = 1
        default_cooldown_seconds = 900
        agents = @(
            [ordered]@{
                name = 'Commit'
                route = 'active'
                visibility = 'picker-visible'
                min_prompt_confidence = 0.74
                min_behavior_confidence = 0.75
                cooldown_seconds = 900
                min_behavior_events = 1
                hint = 'Routing hint: Commit specialist fits this git lifecycle flow (stage/commit/push/tag).'
                prompt_patterns = @('\bstage(?: and)? commit\b', '\bcommit(?: message| my changes)?\b', '\bpush(?: my changes| to origin)?\b', '\btag(?: this version| as v)?\b', '\bcreate (?:a )?release\b')
                behavior = [ordered]@{
                    tool_names = @('run_in_terminal', 'terminal', 'runCommands')
                    command_patterns = @('\bgit\s+(add|commit|push|tag|switch|checkout|merge|rebase|cherry-pick)\b', '\bgit\s+status\b')
                }
            },
            [ordered]@{
                name = 'Organise'
                route = 'active'
                visibility = 'internal'
                min_prompt_confidence = 0.76
                min_behavior_confidence = 0.78
                cooldown_seconds = 1200
                min_behavior_events = 1
                hint = 'Routing hint: Organise specialist fits this file-move, path-fix, or repository-reshape workflow.'
                prompt_patterns = @('\b(?:organize|organise|reorganize|reorganise)\b', '\bmove files?\b', '\bfix paths?\b', '\brestructure\b', '\brename (?:folders?|directories|files?)\b')
                behavior = [ordered]@{
                    tool_names = @('run_in_terminal', 'runCommands')
                    command_patterns = @('\bgit\s+mv\b', '\bmv\s+[^\n]+')
                }
            },
            [ordered]@{
                name = 'Code'
                route = 'active'
                visibility = 'picker-visible'
                min_prompt_confidence = 0.76
                min_behavior_confidence = 0.78
                cooldown_seconds = 1200
                min_behavior_events = 1
                require_prompt_and_behavior = $true
                hint = 'Routing hint: Code specialist fits this multi-step implementation or refactor workflow.'
                prompt_patterns = @('\bimplement\b', '\brefactor\b', '\bfeature\b', '\badd (?:pagination|support|workflow|behavior|tests?)\b', '\bwrite (?:or update )?tests?\b', '\bbugfix\b')
                suppress_patterns = @('\b(review|audit|health check|security|research|upstream|docs?|documentation|readme|plan|break down|roadmap|scoping|root cause|regression|debug(?:ger)?|extensions?|profile|setup(?: from)?|update your instructions|restore instructions|factory restore|reinstall instructions|organi[sz]e|reorgani[sz]e|move files?|fix paths?)\b')
                behavior = [ordered]@{
                    tool_names = @('create_file', 'replace_string_in_file', 'multi_replace_string_in_file', 'editFiles', 'writeFile')
                }
            }
            [ordered]@{
                name = 'Fast'
                route = 'active'
                visibility = 'picker-visible'
                min_prompt_confidence = 0.76
                min_behavior_confidence = 0.76
                cooldown_seconds = 900
                min_behavior_events = 1
                require_prompt_and_behavior = $true
                hint = 'Routing hint: Fast specialist fits this quick-question or lightweight single-file workflow.'
                prompt_patterns = @('\bquick question\b', '\bsyntax lookup\b', '\bwhat does this regex match\b', '\bfix (?:the )?typo\b', '\bsingle-file(?: edit)?\b', '\bwc\s+-l\b')
                suppress_patterns = @('\b(implement|refactor|feature|bugfix|write tests?|review|audit|health check|security|research|upstream|docs?|documentation|readme|plan|break down|roadmap|scoping|root cause|regression|debug(?:ger)?|extensions?|profile|setup(?: from)?|update your instructions|restore instructions|factory restore|reinstall instructions|organi[sz]e|reorgani[sz]e|move files?|fix paths?|stage(?: and)? commit|push(?: my changes| to origin)?|create (?:a )?release)\b')
                behavior = [ordered]@{
                    tool_names = @('run_in_terminal', 'read_file', 'editFiles')
                }
            }
            [ordered]@{
                name = 'Review'
                route = 'active'
                visibility = 'picker-visible'
                min_prompt_confidence = 0.76
                min_behavior_confidence = 0.78
                cooldown_seconds = 1200
                min_behavior_events = 1
                hint = 'Routing hint: Review specialist fits this formal code-review or architecture-critique workflow.'
                prompt_patterns = @('\breview\b', '\bcode review\b', '\bpr review\b', '\barchitectural review\b', '\bfindings\b')
                behavior = [ordered]@{
                    tool_names = @('get_changed_files', 'vscode_listCodeUsages')
                    command_patterns = @()
                }
            },
            [ordered]@{
                name = 'Audit'
                route = 'active'
                visibility = 'picker-visible'
                min_prompt_confidence = 0.78
                min_behavior_confidence = 0.8
                cooldown_seconds = 1800
                min_behavior_events = 1
                hint = 'Routing hint: Audit specialist fits this health-check, security, or residual-risk assessment flow.'
                prompt_patterns = @('\baudit\b', '\bhealth check\b', '\bsecurity audit\b', '\bscan for secrets?\b', '\bvulnerabilit(?:y|ies)\b', '\bresidual risk\b')
                behavior = [ordered]@{
                    tool_names = @('run_in_terminal', 'runCommands')
                    command_patterns = @('\b(copilot_audit\.py|tests/scripts/test-copilot-audit\.sh|scan-secrets)\b', '\b(?:npm\s+audit|pip-audit)\b')
                }
            },
            [ordered]@{
                name = 'Explore'
                route = 'active'
                visibility = 'picker-visible'
                min_prompt_confidence = 0.74
                min_behavior_confidence = 0.72
                cooldown_seconds = 1200
                min_behavior_events = 2
                hint = 'Routing hint: Explore specialist fits this read-only inventory/search workflow.'
                prompt_patterns = @('\bexplore\b', '\bread-only\b', '\bfind (?:all|where|which)\b', '\binventory\b', '\bsearch (?:the )?(?:repo|codebase|workspace)\b', '\bwhere is\b')
                behavior = [ordered]@{
                    tool_names = @('read_file', 'file_search', 'grep_search', 'semantic_search', 'list_dir', 'vscode_listCodeUsages')
                    path_patterns = @()
                }
            },
            [ordered]@{
                name = 'Extensions'
                route = 'active'
                visibility = 'internal'
                min_prompt_confidence = 0.78
                min_behavior_confidence = 0.78
                cooldown_seconds = 1200
                min_behavior_events = 1
                hint = 'Routing hint: Extensions specialist fits this VS Code extension or profile-management workflow.'
                prompt_patterns = @('\bextensions?\b', '\bvs code extensions?\b', '\bprofile\b', '\bworkspace recommendation\b', '\bsync extensions?\b')
                behavior = [ordered]@{
                    tool_names = @('get_active_profile', 'list_profiles', 'get_workspace_profile_association', 'ensure_repo_profile', 'get_installed_extensions', 'install_extension', 'uninstall_extension', 'sync_extensions_with_recommendations')
                    command_patterns = @()
                }
            },
            [ordered]@{
                name = 'Planner'
                route = 'active'
                visibility = 'internal'
                min_prompt_confidence = 0.76
                min_behavior_confidence = 0.76
                cooldown_seconds = 1200
                min_behavior_events = 1
                hint = 'Routing hint: Planner specialist fits this scoped execution-planning workflow.'
                prompt_patterns = @('\bplan\b', '\bbreak down\b', '\bexecution plan\b', '\btask breakdown\b', '\broadmap\b', '\bscoping\b')
                behavior = [ordered]@{
                    tool_names = @('read_file', 'file_search', 'grep_search', 'semantic_search', 'list_dir')
                    path_patterns = @()
                }
            },
            [ordered]@{
                name = 'Docs'
                route = 'active'
                visibility = 'internal'
                min_prompt_confidence = 0.76
                min_behavior_confidence = 0.76
                cooldown_seconds = 1200
                min_behavior_events = 1
                hint = 'Routing hint: Docs specialist fits this documentation or migration-note workflow.'
                prompt_patterns = @('\bdocument(?:ation)?\b', '\bupdate (?:the )?(?:readme|docs?)\b', '\bwrite (?:a )?(?:readme|guide|migration note)\b', '\bwalkthrough\b', '\buser-facing docs?\b')
                behavior = [ordered]@{
                    tool_names = @('create_file', 'replace_string_in_file', 'multi_replace_string_in_file', 'editFiles', 'writeFile')
                    path_patterns = @('\.md$')
                }
            },
            [ordered]@{
                name = 'Debugger'
                route = 'active'
                visibility = 'internal'
                min_prompt_confidence = 0.78
                min_behavior_confidence = 0.8
                cooldown_seconds = 1200
                min_behavior_events = 1
                hint = 'Routing hint: Debugger specialist fits this root-cause and regression-diagnosis workflow.'
                prompt_patterns = @('\bdebug(?:ger)?\b', '\broot cause\b', '\bregression\b', '\bfailing test\b', '\bdiagnos(?:e|is)\b')
                behavior = [ordered]@{
                    tool_names = @('run_in_terminal', 'runCommands', 'get_terminal_output')
                    command_patterns = @('\b(?:pytest|npm\s+test|pnpm\s+test|yarn\s+test|go\s+test|cargo\s+test|bash\s+tests/run-all\.sh)\b', '\btraceback\b')
                }
            },
            [ordered]@{
                name = 'Researcher'
                route = 'active'
                visibility = 'internal'
                min_prompt_confidence = 0.78
                min_behavior_confidence = 0.78
                cooldown_seconds = 1800
                min_behavior_events = 1
                hint = 'Routing hint: Researcher specialist fits this external-docs and version-check request.'
                prompt_patterns = @('\bresearch\b', '\blatest docs?\b', '\bupstream\b', '\bversion-specific\b', '\bexternal docs?\b', '\bapi behavior\b')
                behavior = [ordered]@{
                    tool_names = @('fetch_webpage', 'mcp_fetch_fetch', 'fetch', 'github_repo')
                    command_patterns = @()
                }
            },
            [ordered]@{
                name = 'Setup'
                route = 'guarded'
                visibility = 'picker-visible'
                min_prompt_confidence = 0.92
                min_behavior_confidence = 0.86
                cooldown_seconds = 3600
                min_behavior_events = 1
                require_prompt_and_behavior = $true
                block_in_template_repo = $true
                hint = 'Routing hint: Setup specialist fits this lifecycle-only setup/update/restore flow.'
                prompt_patterns = @('setup from asafelobotomy/copilot-instructions-template', '\bupdate your instructions\b', '\bcheck for instruction updates\b', '\brestore instructions from backup\b', '\bfactory restore instructions\b', '\breinstall instructions from scratch\b')
                suppress_patterns = @('\b(add|implement|refactor|fix|feature|bug|test|lint|build|code|script)\b')
                behavior = [ordered]@{
                    tool_names = @('run_in_terminal', 'runCommands')
                    command_patterns = @('\b(SETUP\.md|UPDATE\.md)\b', '\b(update your instructions|factory restore|restore instructions from backup)\b')
                    path_patterns = @('^(SETUP|UPDATE)\.md$')
                }
            }
        )
    }
}

function Get-RoutingManifest {
    if (Test-Path $routingManifestPath) {
        try {
            $loaded = Get-Content $routingManifestPath -Raw | ConvertFrom-Json -AsHashtable
            if ($loaded -and $loaded['agents']) {
                return $loaded
            }
        } catch {}
    }
    return Get-DefaultRoutingManifest
}

function Get-RoutingIndex([hashtable]$Manifest) {
    $index = [ordered]@{}
    foreach ($entry in @($Manifest['agents'])) {
        if ($null -eq $entry) { continue }
        $name = [string]($entry['name'] ?? '')
        if ($name) { $index[$name] = $entry }
    }
    return $index
}

function Test-TemplateRepo {
    (Test-Path 'template/copilot-instructions.md') -and (Test-Path '.github/copilot-instructions.md')
}

function Get-CommandText([object]$Payload) {
    $toolInput = $Payload.tool_input
    if ($null -eq $toolInput) { return '' }
    foreach ($key in @('command', 'cmd', 'script', 'query', 'goal', 'explanation')) {
        $value = $toolInput.$key
        if ($null -ne $value -and [string]$value) {
            return [string]$value
        }
    }
    return ''
}

function Test-RegexPattern([string]$Text, [string]$Pattern) {
    if (-not [string]$Pattern) { return $false }
    if ($null -eq $Text) { $Text = '' }
    try {
        return [System.Text.RegularExpressions.Regex]::IsMatch(
            $Text,
            $Pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    } catch {
        return $false
    }
}

function Get-RegexMatches([string]$Text, [object[]]$Patterns) {
    $matchedPatterns = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in @($Patterns)) {
        if (-not [string]$pattern) { continue }
        if (Test-RegexPattern $Text $pattern) { $matchedPatterns.Add([string]$pattern) }
    }
    return @($matchedPatterns)
}

function Get-PromptRouteCandidate([string]$Prompt, [hashtable]$Manifest) {
    if (-not $Prompt) { return $null }
    $best = $null
    foreach ($entry in @($Manifest['agents'])) {
        if ($null -eq $entry) { continue }
        $routeMode = [string]($entry['route'] ?? 'inactive')
        if ($routeMode -notin @('active', 'guarded')) { continue }
        $suppressed = $false
        foreach ($pattern in @($entry['suppress_patterns'])) {
            if (Test-RegexPattern $Prompt $pattern) { $suppressed = $true; break }
        }
        if ($suppressed) { continue }
        $promptMatches = Get-RegexMatches $Prompt @($entry['prompt_patterns'])
        if ($promptMatches.Count -eq 0) { continue }
        $confidence = [Math]::Min(0.99, 0.62 + (0.14 * $promptMatches.Count))
        if ($routeMode -eq 'guarded') { $confidence = [Math]::Min(0.99, $confidence + 0.08) }
        $minimum = [double]($entry['min_prompt_confidence'] ?? 0.75)
        if ($confidence -lt $minimum) { continue }
        $candidate = [ordered]@{
            agent = [string]$entry['name']
            confidence = $confidence
            reason = "prompt:$($promptMatches[0])"
            route = $routeMode
        }
        if ($null -eq $best -or [double]$candidate['confidence'] -gt [double]$best['confidence']) {
            $best = $candidate
        }
    }
    return $best
}

function Get-BehaviorRouteCandidate([object]$Payload, [hashtable]$State, [hashtable]$Manifest) {
    $toolName = [string]($Payload.tool_name ?? '')
    $commandText = Get-CommandText $Payload
    $paths = @((Get-ToolPaths $Payload))
    $currentCandidate = [string]($State['route_candidate'] ?? '')
    $best = $null
    foreach ($entry in @($Manifest['agents'])) {
        if ($null -eq $entry) { continue }
        $routeMode = [string]($entry['route'] ?? 'inactive')
        if ($routeMode -notin @('active', 'guarded')) { continue }
        if ([bool]($entry['require_prompt_and_behavior'] ?? $false) -and $currentCandidate -and [string]$entry['name'] -ne $currentCandidate) {
            continue
        }
        $behavior = $entry['behavior']
        if ($null -eq $behavior) { $behavior = [ordered]@{} }
        $commandPatterns = if ($null -eq $behavior['command_patterns']) { @() } else { @($behavior['command_patterns']) }
        $pathPatterns = if ($null -eq $behavior['path_patterns']) { @() } else { @($behavior['path_patterns']) }
        $score = 0.0
        $reason = ''
        $commandMatched = $false
        $pathMatched = $false

        if ($toolName -and (@($behavior['tool_names']) -contains $toolName)) {
            $score += 0.48
            if (-not $reason) { $reason = "tool:$toolName" }
        }

        foreach ($pattern in $commandPatterns) {
            if (-not [string]$pattern) { continue }
            if (Test-RegexPattern $commandText $pattern) {
                $score += 0.32
                if (-not $reason) { $reason = "command:$pattern" }
                $commandMatched = $true
                break
            }
        }

        foreach ($pattern in $pathPatterns) {
            if (-not [string]$pattern) { continue }
            $matched = $false
            foreach ($pathText in $paths) {
                if (Test-RegexPattern ([string]$pathText) $pattern) { $matched = $true; break }
            }
            if ($matched) {
                $score += 0.24
                if (-not $reason) { $reason = "path:$pattern" }
                $pathMatched = $true
                break
            }
        }

        if ($commandPatterns.Count -gt 0 -and -not $commandMatched -and -not $pathMatched) {
            continue
        }

        if ($score -le 0) { continue }

        $signalCounts = $State['route_signal_counts']
        if ($null -eq $signalCounts) { $signalCounts = [ordered]@{} }
        $seenCount = [int]($signalCounts[[string]$entry['name']] ?? 0) + 1
        $minimumEvents = [int]($entry['min_behavior_events'] ?? 1)
        $confidence = [Math]::Min(0.99, 0.52 + $score)
        $minimum = [double]($entry['min_behavior_confidence'] ?? 0.7)
        if ($seenCount -lt $minimumEvents -or $confidence -lt $minimum) { continue }

        $candidate = [ordered]@{
            agent = [string]$entry['name']
            confidence = $confidence
            reason = $reason
            seen_count = $seenCount
            route = $routeMode
        }
        if ($null -eq $best -or [double]$candidate['confidence'] -gt [double]$best['confidence']) {
            $best = $candidate
        }
    }
    return $best
}

function Test-ShouldEmitRouteHint([hashtable]$State, [hashtable]$Entry, [string]$AgentName) {
    $emitted = @($State['route_emitted_agents'])
    if ($emitted -contains $AgentName) { return $false }
    $cooldown = [int]($Entry['cooldown_seconds'] ?? 0)
    if ($cooldown -le 0) { $cooldown = [int]($routingManifest['default_cooldown_seconds'] ?? 900) }
    $lastHintEpoch = [int64]($State['route_last_hint_epoch'] ?? 0)
    if ($lastHintEpoch -gt 0 -and ($now - $lastHintEpoch) -lt $cooldown) { return $false }
    if ([bool]($State['route_emitted'] ?? $false) -and [string]($State['route_candidate'] ?? '') -eq $AgentName) { return $false }
    return $true
}

function Get-RoutingRosterText([hashtable]$Manifest) {
    $direct = New-Object System.Collections.Generic.List[string]
    $internal = New-Object System.Collections.Generic.List[string]
    $guarded = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($Manifest['agents'])) {
        if ($null -eq $entry) { continue }
        $routeMode = [string]($entry['route'] ?? 'inactive')
        if ($routeMode -notin @('active', 'guarded')) { continue }
        $name = [string]($entry['name'] ?? '')
        if (-not $name) { continue }
        if ($routeMode -eq 'guarded') {
            $guarded.Add($name)
        } elseif ([string]($entry['visibility'] ?? 'internal') -eq 'picker-visible') {
            $direct.Add($name)
        } else {
            $internal.Add($name)
        }
    }
    $parts = New-Object System.Collections.Generic.List[string]
    if ($direct.Count -gt 0) { $parts.Add('specialists: ' + ($direct -join ', ')) }
    if ($internal.Count -gt 0) { $parts.Add('internal: ' + ($internal -join ', ')) }
    if ($guarded.Count -gt 0) { $parts.Add('guarded: ' + ($guarded -join ', ')) }
    if ($parts.Count -eq 0) { return 'specialists: Commit, Review, Audit, Explore | internal: Organise, Extensions, Planner, Docs, Debugger, Researcher | guarded: Setup' }
    return ($parts -join ' | ')
}

$defaultPolicy = Get-DefaultPolicy
$policy = Get-Policy
$routingManifest = Get-RoutingManifest
$routingIndex = Get-RoutingIndex $routingManifest
$retrospectivePolicy = if ($policy['retrospective']) { $policy['retrospective'] } else { $defaultPolicy['retrospective'] }
$retroThresholds = if ($retrospectivePolicy['thresholds']) { $retrospectivePolicy['thresholds'] } else { $defaultPolicy['retrospective']['thresholds'] }
$retroModifiedThresholds = if ($retroThresholds['modified_files']) { $retroThresholds['modified_files'] } else { $defaultPolicy['retrospective']['thresholds']['modified_files'] }
$retroElapsedThresholds = if ($retroThresholds['elapsed_minutes']) { $retroThresholds['elapsed_minutes'] } else { $defaultPolicy['retrospective']['thresholds']['elapsed_minutes'] }
$idleGapMinutes = [int]($retroThresholds['idle_gap_minutes'] ?? 10)
$healthDigestConfig = if ($retrospectivePolicy['health_digest']) { $retrospectivePolicy['health_digest'] } else { $defaultPolicy['retrospective']['health_digest'] }
$healthDigestMinSpacingSeconds = [int]($healthDigestConfig['min_emit_spacing_seconds'] ?? 120)
$retroMessages = if ($retrospectivePolicy['messages']) { $retrospectivePolicy['messages'] } else { $defaultPolicy['retrospective']['messages'] }
$sessionStartGuidance = [string]($retroMessages['session_start_guidance'] ?? $defaultPolicy['retrospective']['messages']['session_start_guidance'])
$explicitSystemMessage = [string]($retroMessages['explicit_system'] ?? $defaultPolicy['retrospective']['messages']['explicit_system'])
$stopReflectInstruction = [string]($retroMessages['stop_reflect_instruction'] ?? $defaultPolicy['retrospective']['messages']['stop_reflect_instruction'])
$acceptedReason = [string]($retroMessages['accepted_reason'] ?? $defaultPolicy['retrospective']['messages']['accepted_reason'])

$state = Get-State
$providedId = if ($payload.sessionId) { [string]$payload.sessionId } else { '' }
$sessionId = if ($providedId) {
    $providedId
} elseif ($Trigger -eq 'session_start') {
    'local-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
} else {
    if ($state['session_id']) { [string]$state['session_id'] } else { 'unknown' }
}
$state.session_id = $sessionId
$state.last_trigger = $Trigger

if ($Trigger -eq 'session_start') {
    $priors = Get-SessionPriors
    $state.session_state = 'pending'
    $state.retrospective_state = 'idle'
    $state.last_write_epoch = $now
    $state.session_start_epoch = $now
    $state.session_start_git_count = Get-GitModifiedFileCount
    $state.task_window_start_epoch = 0
    $state.last_raw_tool_epoch = 0
    $state.active_work_seconds = 0
    $state.copilot_edit_count = 0
    $state.tool_call_counter = 0
    $state.intent_phase = 'quiet'
    $state.intent_phase_epoch = $now
    $state.intent_phase_version = 1
    $state.last_digest_key = ''
    $state.last_digest_epoch = 0
    $state.digest_emit_count = 0
    $state.overlay_sensitive_surface = $false
    $state.overlay_parity_required = $false
    $state.overlay_verification_expected = $false
    $state.overlay_decision_capture_needed = $false
    $state.overlay_retro_requested = $false
    $state.signal_edit_started = $false
    $state.signal_scope_supporting = $false
    $state.signal_scope_strong = $false
    $state.signal_work_supporting = $false
    $state.signal_work_strong = $false
    $state.signal_compaction_seen = $false
    $state.signal_idle_reset_seen = $false
    $state.signal_cross_cutting = $false
    $state.signal_scope_widening = $false
    $state.signal_reflection_likely = $false
    $state.route_candidate = ''
    $state.route_reason = ''
    $state.route_confidence = 0.0
    $state.route_source = ''
    $state.route_emitted = $false
    $state.route_epoch = 0
    $state.route_last_hint_epoch = 0
    $state.route_emitted_agents = @()
    $state.route_signal_counts = [ordered]@{}
    $state.changed_path_families = @()
    $state.touched_files_sample = @()
    $state.unique_touched_file_count = 0
    foreach ($key in @($priors.Keys)) {
        $state[$key] = $priors[$key]
    }
    Set-Sentinel $sessionId 'pending'
    Add-HeartbeatEvent $Trigger
    Invoke-PruneEvents
    Save-State $state
    $dtStr = Convert-EpochToUtcString $now
    $timingHint = Get-SessionMedians
    $ctxParts = @("Session started at $dtStr.")
    if ($timingHint) { $ctxParts += $timingHint }
    $ctxParts += "Routing roster: $(Get-RoutingRosterText $routingManifest)."
    $ctxParts += $sessionStartGuidance
    $additionalCtx = $ctxParts -join ' '
    Write-JsonOutput @{ continue = $true; hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = $additionalCtx } }
    exit 0
}

if ($Trigger -eq 'pre_tool') {
    $signalCounts = $state['route_signal_counts']
    if ($null -eq $signalCounts) { $signalCounts = [ordered]@{} }
    $behaviorCandidate = Get-BehaviorRouteCandidate $payload $state $routingManifest
    if ($null -ne $behaviorCandidate) {
        $agentKey = [string]$behaviorCandidate['agent']
        $signalCounts[$agentKey] = [int]($signalCounts[$agentKey] ?? 0) + 1
        $state.route_signal_counts = $signalCounts
    }

    $currentCandidate = [string]($state['route_candidate'] ?? '')
    $currentConfidence = [double]($state['route_confidence'] ?? 0.0)

    if ($null -ne $behaviorCandidate) {
        $agentName = [string]$behaviorCandidate['agent']
        $entry = $routingIndex[$agentName]
        if ($null -eq $entry) { $entry = [ordered]@{} }
        $requiresPromptAndBehavior = [bool]($entry['require_prompt_and_behavior'] ?? $false)
        $guarded = ([string]($entry['route'] ?? '') -eq 'guarded')
        if ($requiresPromptAndBehavior) {
            if ($currentCandidate -ne $agentName) {
                Save-State $state
                Write-JsonOutput @{ continue = $true }
                exit 0
            }
        }
        if ($guarded) {
            if ([bool]($entry['block_in_template_repo'] ?? $false) -and (Test-TemplateRepo)) {
                Save-State $state
                Write-JsonOutput @{ continue = $true }
                exit 0
            }
        }

        if ($currentCandidate -eq $agentName) {
            $state.route_confidence = [Math]::Max($currentConfidence, [double]$behaviorCandidate['confidence'])
            $existingReason = [string]($state['route_reason'] ?? '')
            if ($existingReason) {
                $state.route_reason = "$existingReason; behavior:$($behaviorCandidate['reason'])"
            } else {
                $state.route_reason = "behavior:$($behaviorCandidate['reason'])"
            }
            $state.route_source = 'prompt+behavior'
        } elseif (-not $currentCandidate) {
            $state.route_candidate = $agentName
            $state.route_confidence = [double]$behaviorCandidate['confidence']
            $state.route_reason = "behavior:$($behaviorCandidate['reason'])"
            $state.route_source = 'behavior'
            $state.route_emitted = $false
            $state.route_epoch = $now
        }

        $candidateName = [string]($state['route_candidate'] ?? '')
        $candidateEntry = $routingIndex[$candidateName]
        if ($null -eq $candidateEntry) { $candidateEntry = [ordered]@{} }
        $candidateConfidence = [double]($state['route_confidence'] ?? 0.0)
        $minimum = [double]($candidateEntry['min_behavior_confidence'] ?? 0.7)

        if ($candidateName -and $agentName -eq $candidateName -and $candidateConfidence -ge $minimum -and (Test-ShouldEmitRouteHint $state $candidateEntry $candidateName)) {
            $hint = [string]($candidateEntry['hint'] ?? "Routing hint: $candidateName specialist may be the best fit.")
            $emittedAgents = @($state['route_emitted_agents'])
            $emittedAgents += $candidateName
            $state.route_emitted_agents = $emittedAgents
            $state.route_emitted = $true
            $state.route_last_hint_epoch = $now
            $state.last_write_epoch = $now
            Save-State $state
            Write-JsonOutput @{
                continue = $true
                hookSpecificOutput = @{
                    hookEventName = 'PreToolUse'
                    additionalContext = "$hint Confidence $([Math]::Round($candidateConfidence, 2)) ($($state['route_source']))."
                }
            }
            exit 0
        }
    }

    $state.last_write_epoch = $now
    Save-State $state
    Write-JsonOutput @{ continue = $true }
    exit 0
}

if ($Trigger -eq 'soft_post_tool') {
    $fileWritingTools = @('create_file', 'replace_string_in_file', 'multi_replace_string_in_file', 'editFiles', 'writeFile')
    $toolName = [string]($payload.tool_name ?? '')
    if ($fileWritingTools -contains $toolName) {
        $state.copilot_edit_count = [int]($state['copilot_edit_count'] ?? 0) + 1
    }

    $idleGapS = $idleGapMinutes * 60
    $taskWindowStart = [int64]($state['task_window_start_epoch'] ?? 0)
    $lastTool = [int64]($state['last_raw_tool_epoch'] ?? 0)
    if ($taskWindowStart -eq 0) {
        $state.task_window_start_epoch = $now
    } elseif ($lastTool -gt 0 -and ($now - $lastTool) -gt $idleGapS) {
        $windowS = [Math]::Max(0, $lastTool - $taskWindowStart)
        $state.active_work_seconds = [int]($state['active_work_seconds'] ?? 0) + $windowS
        $state.task_window_start_epoch = $now
        $state.signal_idle_reset_seen = $true
    }
    $state.last_raw_tool_epoch = $now
    $state.last_write_epoch = $now
    $state.tool_call_counter = [int]($state['tool_call_counter'] ?? 0) + 1

    $last = [int64]($state['last_soft_trigger_epoch'] ?? 0)
    if (($now - $last) -ge 300) {
        $state.last_soft_trigger_epoch = $now
        Add-HeartbeatEvent $Trigger
    }

    $intentUpdate = Update-IntentEngine $state $payload $true
    $state = $intentUpdate['state']
    $digest = [string]($intentUpdate['digest'] ?? '')
    Save-State $state

    if ($digest) {
        Write-JsonOutput @{ continue = $true; hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $digest } }
    } else {
        Write-JsonOutput @{ continue = $true }
    }
    exit 0
}

if ($Trigger -eq 'compaction') {
    $state = Close-WorkWindow $state
    $state.last_compaction_epoch = $now
    $state.last_write_epoch = $now
    Add-HeartbeatEvent $Trigger
    $intentUpdate = Update-IntentEngine $state $null $false
    $state = $intentUpdate['state']
    Save-State $state
    Write-JsonOutput @{ continue = $true }
    exit 0
}

if ($Trigger -in @('user_prompt', 'explicit')) {
    $prompt = [string]($payload.prompt ?? '')
    $promptCandidate = Get-PromptRouteCandidate $prompt $routingManifest
    if ($null -ne $promptCandidate) {
        $state.route_candidate = [string]$promptCandidate['agent']
        $state.route_reason = [string]$promptCandidate['reason']
        $state.route_confidence = [double]$promptCandidate['confidence']
        $state.route_source = 'prompt'
        $state.route_emitted = $false
        $state.route_epoch = $now
        $state.route_signal_counts = [ordered]@{}
    } else {
        $state.route_candidate = ''
        $state.route_reason = ''
        $state.route_confidence = 0.0
        $state.route_source = ''
        $state.route_emitted = $false
        $state.route_epoch = 0
        $state.route_signal_counts = [ordered]@{}
    }
    $retrospectiveRequested = Test-RetrospectiveRequest $prompt
    $heartbeatRequested = Test-HeartbeatRequest $prompt

    if ($retrospectiveRequested) {
        $state.retrospective_state = 'accepted'
    }

    if ($heartbeatRequested -or $retrospectiveRequested) {
        $state.last_explicit_epoch = $now
        $state.last_write_epoch = $now
        Add-HeartbeatEvent 'explicit_prompt' $(if ($heartbeatRequested) { 'heartbeat' } else { 'retrospective' })
        $intentUpdate = Update-IntentEngine $state $null $false
        $state = $intentUpdate['state']
        Save-State $state
        if ($heartbeatRequested) {
            Write-JsonOutput @{ continue = $true; systemMessage = $explicitSystemMessage }
        } else {
            Write-JsonOutput @{ continue = $true }
        }
    } else {
        $state.last_write_epoch = $now
        Save-State $state
        Write-JsonOutput @{ continue = $true }
    }
    exit 0
}

if ($Trigger -eq 'stop') {
    if ($payload.stop_hook_active -eq $true) {
        Write-JsonOutput @{ continue = $true }
        exit 0
    }

    $state = Close-WorkWindow $state
    $startEpoch = if ($state['session_start_epoch']) { [int64]$state['session_start_epoch'] } else { 0 }
    $retroRan = (Test-SentinelComplete) -or (Test-ReflectionComplete $sessionId $startEpoch)

    $durationStart = if ($startEpoch -gt 0) { $startEpoch } else { $now }
    $durationS = [int]($now - $durationStart)
    if ($durationS -lt 0) { $durationS = 0 }

    if ($retroRan) {
        $state.session_state = 'complete'
        $state.retrospective_state = 'complete'
        $state.last_write_epoch = $now
        Set-Sentinel $sessionId 'complete'
        Add-HeartbeatEvent $Trigger 'complete' -DurationS $durationS
        Save-State $state
        Write-JsonOutput @{ continue = $true }
        exit 0
    }

    $retroState = Get-RetrospectiveState $state
    if ($retroState -eq 'accepted') {
        $state.session_state = 'pending'
        $state.last_write_epoch = $now
        Add-HeartbeatEvent $Trigger 'accepted-pending'
        Save-State $state
        Write-JsonOutput @{
            hookSpecificOutput = @{
                hookEventName = 'Stop'
                decision = 'block'
                reason = $acceptedReason
            }
        }
        exit 0
    }

    $retroRecommendation = Get-RetrospectiveRecommendation $state
    if ($retroRecommendation.required -eq $true) {
        $state.session_state = 'pending'
        $state.retrospective_state = 'suggested'
        $state.last_write_epoch = $now
        Add-HeartbeatEvent $Trigger 'reflect-needed'
        Save-State $state
        Write-JsonOutput @{
            hookSpecificOutput = @{
                hookEventName = 'Stop'
                decision = 'block'
                reason = "Significant session ($($retroRecommendation.basis)). $stopReflectInstruction"
            }
        }
        exit 0
    }

    $state.session_state = 'complete'
    $state.retrospective_state = 'not-needed'
    $state.last_write_epoch = $now
    Add-HeartbeatEvent $Trigger 'not-needed' -DurationS $durationS
    Save-State $state
    Write-JsonOutput @{ continue = $true }
    exit 0
}

Write-JsonOutput @{ continue = $true }
