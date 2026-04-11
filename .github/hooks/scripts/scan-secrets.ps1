# purpose:  Scan modified files for leaked secrets at session end
# when:     Stop hook — fires when the agent session ends
# inputs:   JSON via stdin
# outputs:  JSON continuation signal; scan results on stderr
# risk:     read-only
# ESCALATION: block
# STOP LOOP: if stop_hook_active is true in the Stop payload, do not re-enter blocking Stop logic.

$ErrorActionPreference = 'SilentlyContinue'
$inputJson = $input | Out-String

$stopHookActive = $false
if ($inputJson) {
    try {
        $payload = $inputJson | ConvertFrom-Json -ErrorAction Stop
        if ($payload.stop_hook_active -eq $true) {
            $stopHookActive = $true
        }
    } catch {
        $stopHookActive = $false
    }
}

if ($stopHookActive) {
    '{"continue": true}'; exit 0
}

# ---------------------------------------------------------------------------
# Environment variables
#   SCAN_MODE          - "warn" (log only) or "block" (block on findings)
#   SCAN_SCOPE         - "diff" (changed files) or "staged" (staged files)
#   SKIP_SECRETS_SCAN  - "true" to disable scanning
#   SECRETS_ALLOWLIST  - Comma-separated patterns to ignore
# ---------------------------------------------------------------------------

if ($env:SKIP_SECRETS_SCAN -eq 'true') {
    Write-Host "⏭️  Secrets scan skipped (SKIP_SECRETS_SCAN=true)" -ForegroundColor Yellow
    '{"continue": true}'; exit 0
}

# Verify git is available and we are in a repo
$gitCheck = git rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or $gitCheck -ne 'true') {
    Write-Host "⚠️  Not in a git repository, skipping secrets scan" -ForegroundColor Yellow
    '{"continue": true}'; exit 0
}

$Mode  = if ($env:SCAN_MODE)  { $env:SCAN_MODE }  else { 'warn' }
$Scope = if ($env:SCAN_SCOPE) { $env:SCAN_SCOPE } else { 'diff' }

# Secret patterns: Name, Severity, Regex
$Patterns = @(
    [PSCustomObject]@{ Name = 'AWS_ACCESS_KEY'; Severity = 'critical'; Regex = 'AKIA[0-9A-Z]{16}' }
    [PSCustomObject]@{ Name = 'AWS_SECRET_KEY'; Severity = 'critical'; Regex = 'aws_secret_access_key\s*[:=]\s*[''\"]?[A-Za-z0-9/+=]{40}' }
    [PSCustomObject]@{ Name = 'GCP_API_KEY'; Severity = 'high'; Regex = 'AIza[0-9A-Za-z_-]{35}' }
    [PSCustomObject]@{ Name = 'GITHUB_PAT'; Severity = 'critical'; Regex = 'ghp_[0-9A-Za-z]{36}' }
    [PSCustomObject]@{ Name = 'GITHUB_OAUTH'; Severity = 'critical'; Regex = 'gho_[0-9A-Za-z]{36}' }
    [PSCustomObject]@{ Name = 'GITHUB_APP_TOKEN'; Severity = 'critical'; Regex = 'ghs_[0-9A-Za-z]{36}' }
    [PSCustomObject]@{ Name = 'GITHUB_REFRESH_TOKEN'; Severity = 'critical'; Regex = 'ghr_[0-9A-Za-z]{36}' }
    [PSCustomObject]@{ Name = 'GITHUB_FINE_PAT'; Severity = 'critical'; Regex = 'github_pat_[0-9A-Za-z_]{82}' }
    [PSCustomObject]@{ Name = 'PRIVATE_KEY'; Severity = 'critical'; Regex = '-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----' }
    [PSCustomObject]@{ Name = 'GENERIC_SECRET'; Severity = 'high'; Regex = '(secret|token|password|passwd|pwd|api[_-]?key|apikey|access[_-]?key|auth[_-]?token|client[_-]?secret)\s*[:=]\s*[''\"]?[A-Za-z0-9_/+=~.-]{8,}' }
    [PSCustomObject]@{ Name = 'CONNECTION_STRING'; Severity = 'high'; Regex = '(mongodb(\+srv)?|postgres(ql)?|mysql|redis|amqp|mssql)://[^\s''\"]{10,}' }
    [PSCustomObject]@{ Name = 'SLACK_TOKEN'; Severity = 'high'; Regex = 'xox[baprs]-[0-9]{10,}-[0-9A-Za-z-]+' }
    [PSCustomObject]@{ Name = 'STRIPE_SECRET_KEY'; Severity = 'critical'; Regex = 'sk_live_[0-9A-Za-z]{24,}' }
    [PSCustomObject]@{ Name = 'NPM_TOKEN'; Severity = 'high'; Regex = 'npm_[0-9A-Za-z]{36}' }
    [PSCustomObject]@{ Name = 'JWT_TOKEN'; Severity = 'medium'; Regex = 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' }
)

# Collect files to scan
$Files = @()
if ($Scope -eq 'staged') {
    $Files = git diff --cached --name-only --diff-filter=ACMR 2>$null | Where-Object { $_ }
} else {
    $Files = git diff --name-only --diff-filter=ACMR HEAD 2>$null | Where-Object { $_ }
    if (-not $Files) {
        $Files = git diff --name-only --diff-filter=ACMR 2>$null | Where-Object { $_ }
    }
    $untracked = git ls-files --others --exclude-standard 2>$null | Where-Object { $_ }
    if ($untracked) { $Files = @($Files) + @($untracked) }
}

if (-not $Files -or $Files.Count -eq 0) {
    Write-Host "✨ No modified files to scan" -ForegroundColor Green
    '{"continue": true}'; exit 0
}

# Parse allowlist
$Allowlist = @()
if ($env:SECRETS_ALLOWLIST) {
    $Allowlist = $env:SECRETS_ALLOWLIST -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

# Skip lock files and binary files
$SkipExtensions = @('.lock')
$SkipNames = @('package-lock.json', 'pnpm-lock.yaml', 'go.sum')

$Findings = @()

Write-Host "🔍 Scanning $($Files.Count) modified file(s) for secrets..." -ForegroundColor Cyan

foreach ($filepath in $Files) {
    if (-not (Test-Path $filepath -PathType Leaf)) { continue }
    $filename = Split-Path $filepath -Leaf
    if ($SkipNames -contains $filename) { continue }
    if ($SkipExtensions -contains [System.IO.Path]::GetExtension($filepath)) { continue }

    $lineNum = 0
    foreach ($line in Get-Content $filepath -ErrorAction SilentlyContinue) {
        $lineNum++
        $lineText = [string]$line
        foreach ($pat in $Patterns) {
            $pName = [string]$pat.Name
            $pSev = [string]$pat.Severity
            $pRegex = [string]$pat.Regex
            if (-not $pRegex) { continue }
            $match = [regex]::Match($lineText, $pRegex)
            if (-not $match.Success) { continue }

            $matchVal = $match.Value
            # Skip placeholder / example values
            if ($matchVal -match '(example|placeholder|your[_-]|xxx|changeme|TODO|FIXME|replace[_-]?me|dummy|fake|test[_-]?key|sample)') { continue }
            # Check allowlist
            $allowed = $false
            foreach ($al in $Allowlist) {
                if ($matchVal -like "*$al*") { $allowed = $true; break }
            }
            if ($allowed) { continue }
            # Redact
            $redacted = if ($matchVal.Length -le 12) { '[REDACTED]' } else { $matchVal.Substring(0,4) + '...' + $matchVal.Substring($matchVal.Length - 4) }
            $Findings += [PSCustomObject]@{ File=$filepath; Line=$lineNum; Pattern=$pName; Severity=$pSev; Match=$redacted }
        }
    }
}

if ($Findings.Count -gt 0) {
    Write-Host "" -ForegroundColor Yellow
    Write-Host "⚠️  Found $($Findings.Count) potential secret(s) in modified files:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host ("  {0,-40} {1,-6} {2,-28} {3}" -f 'FILE','LINE','PATTERN','SEVERITY') -ForegroundColor Yellow
    Write-Host ("  {0,-40} {1,-6} {2,-28} {3}" -f '----','----','-------','--------') -ForegroundColor Yellow

    foreach ($f in $Findings) {
        Write-Host ("  {0,-40} {1,-6} {2,-28} {3}" -f $f.File, $f.Line, $f.Pattern, $f.Severity)
    }
    Write-Host ""

    if ($Mode -eq 'block') {
        Write-Host "🚫 Session blocked: resolve the findings above before committing." -ForegroundColor Red
        Write-Host "   Set SCAN_MODE=warn to log without blocking, or add patterns to SECRETS_ALLOWLIST." -ForegroundColor Red
        '{"continue": false}'; exit 0
    } else {
        Write-Host "💡 Review the findings above. Set SCAN_MODE=block to prevent commits with secrets." -ForegroundColor Yellow
    }
} else {
    Write-Host "✅ No secrets detected in $($Files.Count) scanned file(s)" -ForegroundColor Green
}

'{"continue": true}'
