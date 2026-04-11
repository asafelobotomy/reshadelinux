# purpose:  Block dangerous terminal commands before execution
# when:     PreToolUse hook — fires before the agent invokes any tool
# inputs:   JSON via stdin with tool_name and tool_input
# outputs:  JSON with permissionDecision (allow/deny/ask)
# risk:     safe
# ESCALATION: ask

$ErrorActionPreference = 'SilentlyContinue'
$input_json = $input | Out-String

try {
    $data = $input_json | ConvertFrom-Json
} catch {
    '{"continue": true}'; exit 0
}

$toolName = $data.tool_name ?? ''

# Only guard terminal/command tools
if ($toolName -notmatch 'terminal|command|bash|shell') {
    '{"continue": true}'; exit 0
}

$ti = $data.tool_input
$command = ''
if ($null -ne $ti -and $ti.command -is [string]) {
    $command = $ti.command
}

if ([string]::IsNullOrWhiteSpace($command)) {
    [PSCustomObject]@{
        hookSpecificOutput = [PSCustomObject]@{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'ask'
            permissionDecisionReason = 'tool_input.command is required for terminal tools. Falling back to manual confirmation.'
        }
    } | ConvertTo-Json -Depth 5
    exit 0
}

# Blocked patterns — hard deny
$blockedPatterns = @(
    'rm\s+-rf\s+/([^a-zA-Z0-9._-]|$)',
    'rm\s+-rf\s+~([^a-zA-Z0-9._/-]|$)',
    'rm\s+-rf\s+\.($|\s)',
    'DROP\s+TABLE',
    'DROP\s+DATABASE',
    'TRUNCATE\s+TABLE',
    'DELETE\s+FROM\s+.+\s+WHERE\s+1',
    'mkfs\.',
    'dd\s+if=.+of=/dev/',
    ':\(\)\{:\|:&\};:',
    'chmod\s+-R\s+777\s+/([^a-zA-Z0-9._-]|$)',
    'curl\s+.+\|\s*sh',
    'wget\s+.+\|\s*sh'
)

function Test-ReadonlyPatternSearch {
    param(
        [string]$InputCommand
    )

    $trimmed = $InputCommand.Trim()
    if ($trimmed -notmatch '^(rg|grep|findstr)\b' -and $trimmed -notmatch '^git\s+grep\b') {
        return $false
    }

    if ($InputCommand -match '&&|\|\||;|[<>]|\s\|\s' -or $InputCommand.Contains('$(') -or $InputCommand.Contains('`')) {
        return $false
    }

    return $true
}

if (Test-ReadonlyPatternSearch -InputCommand $command) {
    '{"continue": true}'
    exit 0
}

foreach ($pattern in $blockedPatterns) {
    if ($command -imatch $pattern) {
        [PSCustomObject]@{
            hookSpecificOutput = [PSCustomObject]@{
                hookEventName           = 'PreToolUse'
                permissionDecision      = 'deny'
                permissionDecisionReason = "Blocked by security hook: matched destructive pattern '$pattern'"
            }
        } | ConvertTo-Json -Depth 5
        exit 0
    }
}

# Caution patterns — require user confirmation
$cautionPatterns = @(
    'rm\s+-rf',
    'rm\s+-r\s+',
    'chmod\s+-R\s+777',
    'DROP\s+',
    'DELETE\s+FROM',
    'git\s+push.*--force',
    'git\s+reset\s+--hard',
    'git\s+clean\s+-fd',
    'npm\s+publish',
    'cargo\s+publish',
    'pip\s+install\s+--'
)

foreach ($pattern in $cautionPatterns) {
    if ($command -imatch $pattern) {
        $preview = if ($command.Length -gt 200) { $command.Substring(0,200) } else { $command }
        [PSCustomObject]@{
            hookSpecificOutput = [PSCustomObject]@{
                hookEventName           = 'PreToolUse'
                permissionDecision      = 'ask'
                permissionDecisionReason = "Potentially destructive command detected: matches '$pattern'. Requires user confirmation."
                additionalContext       = "The command '$preview' matched a caution pattern. Verify this is intended before proceeding."
            }
        } | ConvertTo-Json -Depth 5
        exit 0
    }
}

# Read-only agent guardrails — Audit, Review, and Explore should not perform
# mutating terminal operations without explicit user approval.
$agentName = ''
try {
    $candidates = @(
        $data.agentName,
        $data.agent_name,
        $data.context.agentName,
        $data.context.agent_name,
        $data.session.agentName,
        $data.session.agent_name
    )
    foreach ($c in $candidates) {
        if ($c -is [string] -and $c.Trim()) {
            $agentName = $c.Trim()
            break
        }
    }
} catch { $agentName = '' }

if ($agentName -match '^(Audit|Review|Explore)$') {
    $readonlyWritePatterns = @(
        '(^|[;&|]\s*)(mkdir|touch|cp|mv|truncate|install)\s',
        '(^|[;&|]\s*)(sed\s+-i|perl\s+-i|tee\s)',
        '(^|[;&|]\s*)(echo|printf).*>+',
        '(^|[;&|]\s*)(git\s+(add|commit|push|reset|checkout|switch|merge|rebase|cherry-pick|revert|tag|stash))',
        '(^|[;&|]\s*)((npm|pnpm|yarn|bun)\s+(install|add|remove|update|upgrade|publish))',
        '(^|[;&|]\s*)(pip|uv\s+pip)\s+install'
    )

    foreach ($rwp in $readonlyWritePatterns) {
        if ($command -imatch $rwp) {
            $preview = if ($command.Length -gt 200) { $command.Substring(0,200) } else { $command }
            [PSCustomObject]@{
                hookSpecificOutput = [PSCustomObject]@{
                    hookEventName           = 'PreToolUse'
                    permissionDecision      = 'ask'
                    permissionDecisionReason = "$agentName is a read-only agent. Mutating terminal commands require explicit user confirmation."
                    additionalContext       = "The command '$preview' appears to mutate files or repository state. Use the Code agent for implementation tasks or confirm this one-off command."
                }
            } | ConvertTo-Json -Depth 5
            exit 0
        }
    }
}

'{"continue": true}'
