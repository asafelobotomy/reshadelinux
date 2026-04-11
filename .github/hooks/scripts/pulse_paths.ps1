$manifestFiles = @(
    'package.json',
    'package-lock.json',
    'pyproject.toml',
    'requirements.txt',
    'requirements-dev.txt',
    'requirements-test.txt',
    'go.mod',
    'Cargo.toml',
    'release-please-config.json',
    '.release-please-manifest.json'
)

function Get-UniquePreserve([object[]]$Items) {
    $seen = @{}
    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Items)) {
        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($seen.ContainsKey($text)) { continue }
        $seen[$text] = $true
        $ordered.Add($text)
    }
    return @($ordered)
}

function Normalize-PathText([string]$RawPath) {
    $pathText = [string]($RawPath ?? '')
    $pathText = ($pathText.Trim() -replace '\\', '/')
    if (-not $pathText) { return '' }
    if ($pathText.StartsWith('./')) {
        $pathText = $pathText.Substring(2)
    }
    if ([System.IO.Path]::IsPathRooted($pathText)) {
        $cwd = (((Get-Location).Path) -replace '\\', '/').TrimEnd('/')
        if ($pathText.StartsWith($cwd + '/')) {
            $pathText = $pathText.Substring($cwd.Length + 1)
        } else {
            $pathText = [System.IO.Path]::GetFileName($pathText)
        }
    }
    return $pathText.TrimStart('/')
}

function Get-PathCandidates([object]$Candidate) {
    $results = @()
    if ($null -eq $Candidate) { return $results }
    if ($Candidate -is [string]) {
        $normalized = Normalize-PathText $Candidate
        if ($normalized) { $results += $normalized }
        return $results
    }
    foreach ($key in @('filePath', 'file', 'path', 'file_path')) {
        $value = $null
        try { $value = $Candidate.$key } catch { $value = $null }
        if ($value -is [string]) {
            $normalized = Normalize-PathText $value
            if ($normalized) { $results += $normalized }
            break
        }
    }
    return $results
}

function Get-ToolPaths([object]$Payload) {
    $toolInput = $Payload.tool_input
    if ($null -eq $toolInput) { return @() }
    $paths = @()
    foreach ($key in @('filePath', 'file', 'path', 'files', 'file_path')) {
        $value = $null
        try { $value = $toolInput.$key } catch { $value = $null }
        if ($null -eq $value) { continue }
        if ($value -is [array]) {
            foreach ($item in $value) {
                $paths += Get-PathCandidates $item
            }
        } else {
            $paths += Get-PathCandidates $value
        }
    }
    return Get-UniquePreserve $paths
}

function Get-PathFamily([string]$PathText) {
    $pathText = Normalize-PathText $PathText
    if (-not $pathText) { return $null }

    $filename = [System.IO.Path]::GetFileName($pathText)
    if ($pathText -like '.copilot/workspace/*') { return 'memory' }
    if ($pathText -like '.github/hooks/*' -or $pathText -like 'template/hooks/*') { return 'hook' }
    if (
        $pathText -like '.github/agents/*' -or
        $pathText -like '.github/prompts/*' -or
        $pathText -like '.github/instructions/*' -or
        $pathText -like '.github/skills/*' -or
        $pathText -like 'template/prompts/*' -or
        $pathText -like 'template/instructions/*' -or
        $pathText -like 'template/skills/*' -or
        @('AGENTS.md', '.github/copilot-instructions.md', 'template/copilot-instructions.md') -contains $pathText
    ) {
        return 'agent'
    }
    if (
        $pathText -like 'tests/*' -or
        $pathText -match '(^|/)(__tests__|test)/' -or
        $pathText -match '\.(test|spec)\.[^/]+$'
    ) {
        return 'tests'
    }
    if (
        $pathText -like '.github/workflows/*' -or
        $pathText -like 'scripts/release/*' -or
        $pathText -like 'scripts/sync/*' -or
            $pathText -like 'scripts/ci/*' -or
        $pathText -like 'scripts/workspace/*'
    ) {
        return 'ci_release'
    }
    if ($manifestFiles -contains $filename) { return 'manifest' }
    if (
        $pathText -like '.vscode/*' -or
        $pathText -match '(^|/)\.[^/]*rc(\.[^/]+)?$' -or
        $pathText -match '\.config\.[^/]+$'
    ) {
        return 'config'
    }
    if (
        $pathText.EndsWith('.md') -or
        @('README.md', 'CHANGELOG.md', 'MIGRATION.md', 'SETUP.md', 'UPDATE.md', 'VERSION.md', 'CLAUDE.md', 'llms.txt') -contains $filename
    ) {
        return 'docs'
    }
    if ($pathText -like 'scripts/*' -or $pathText.EndsWith('.py') -or $pathText.EndsWith('.sh') -or $pathText.EndsWith('.ps1')) {
        return 'runtime'
    }
    if ($pathText.EndsWith('.json') -or $pathText.EndsWith('.yml') -or $pathText.EndsWith('.yaml') -or $pathText.EndsWith('.toml')) {
        return 'config'
    }
    return $null
}

function Test-PathRequiresParity([string]$PathText) {
    $pathText = Normalize-PathText $PathText
    if (-not $pathText) { return $false }
    return (
        $pathText -like '.github/hooks/*' -or
        $pathText -like 'template/hooks/*' -or
        $pathText -like '.github/skills/*' -or
        $pathText -like 'template/skills/*' -or
        $pathText -like '.github/instructions/*' -or
        $pathText -like 'template/instructions/*' -or
        $pathText -like '.github/prompts/*' -or
        $pathText -like 'template/prompts/*' -or
        @('.copilot/workspace/operations/workspace-index.json', 'template/workspace/operations/workspace-index.json') -contains $pathText
    )
}

function Update-TouchedFiles([hashtable]$State, [object[]]$Paths) {
    if (@($Paths).Count -eq 0) { return $State }
    $existing = @($State['touched_files_sample']) + @($Paths)
    $touched = Get-UniquePreserve $existing
    if ($touched.Count -gt 20) {
        $touched = @($touched[($touched.Count - 20)..($touched.Count - 1)])
    }
    $families = @($State['changed_path_families'])
    foreach ($pathText in @($Paths)) {
        $family = Get-PathFamily $pathText
        if ($family -and -not ($families -contains $family)) {
            $families += $family
        }
    }
    $State['touched_files_sample'] = @($touched)
    $State['unique_touched_file_count'] = @($touched).Count
    $State['changed_path_families'] = @($families)
    return $State
}
