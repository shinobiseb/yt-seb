$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$Scripts = @(
    (Join-Path $RepoRoot 'src\yt-seb.ps1'),
    (Join-Path $RepoRoot 'src\Uninstall-yt-seb.ps1'),
    (Join-Path $RepoRoot 'install.ps1'),
    (Join-Path $RepoRoot 'installer\build.ps1')
)

foreach ($Script in $Scripts) {
    $Tokens = $null
    $Errors = $null
    [Management.Automation.Language.Parser]::ParseFile($Script, [ref]$Tokens, [ref]$Errors) | Out-Null
    if ($Errors.Count) {
        throw "PowerShell syntax failed for $Script`: $($Errors[0].Message)"
    }
}

$CommandSource = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\yt-seb.ps1') -Raw
if ($CommandSource -notmatch '\$SearchResultCount\s*=\s*5') {
    throw 'yt-seb must search exactly five results.'
}
if ($CommandSource -notmatch '\$Selected\s*=\s*\$Candidates\s*\|\s*Select-Object -First 1') {
    throw 'yt-seb must preserve YouTube relevance order.'
}
if ($CommandSource -notmatch "-si") {
    throw 'The development command must implement the -si flag.'
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'src\analyze-audio.mjs'))) {
    throw 'The local audio analyzer is missing.'
}

Write-Host 'Static tests passed.' -ForegroundColor Green
