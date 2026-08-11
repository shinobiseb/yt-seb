param(
    [string]$ExpectedInstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\yt-seb'),
    [switch]$RequireInstalledCommand
)

$ErrorActionPreference = 'Stop'

$ExpectedScripts = @(
    (Join-Path $ExpectedInstallRoot 'yt-seb.ps1'),
    (Join-Path $ExpectedInstallRoot 'yt-seb.cmd')
)
$Commands = @(Get-Command yt-seb -All -ErrorAction SilentlyContinue)

if ($Commands.Count -eq 0) {
    $Message = 'yt-seb is not currently resolvable from PATH.'
    if ($RequireInstalledCommand) { throw $Message }
    Write-Warning "$Message Install yt-seb before running the strict command smoke test."
    return
}

$ActivePath = [IO.Path]::GetFullPath([string]$Commands[0].Source)
$ExpectedMatch = $ExpectedScripts | Where-Object {
    [IO.Path]::GetFullPath($_).Equals($ActivePath, [StringComparison]::OrdinalIgnoreCase)
} | Select-Object -First 1

if (-not $ExpectedMatch) {
    $Candidates = ($Commands | ForEach-Object Source) -join "`n  - "
    $Message = @"
The active yt-seb command is '$ActivePath', not the installed development command
under '$ExpectedInstallRoot'. An older PATH entry is shadowing the intended command.
Resolved candidates:
  - $Candidates
"@
    if ($RequireInstalledCommand) { throw $Message }
    Write-Warning $Message
    return
}

$InstalledScript = Join-Path $ExpectedInstallRoot 'yt-seb.ps1'
if (-not (Test-Path -LiteralPath $InstalledScript -PathType Leaf)) {
    throw "The active install is missing '$InstalledScript'."
}
$InstalledSource = Get-Content -LiteralPath $InstalledScript -Raw
if ($InstalledSource -notmatch '(?i)-si' -or
    $InstalledSource -notmatch 'Resolve-SongMetadata') {
    throw "The active yt-seb script at '$InstalledScript' does not contain the development song-info pipeline."
}

Write-Host "Installed command-resolution smoke test passed: $ActivePath" -ForegroundColor Green
