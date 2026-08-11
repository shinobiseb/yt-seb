$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$SourceRoot = Join-Path $RepoRoot 'src'
$Output = Join-Path $RepoRoot 'dist\yt-seb Setup.exe'
$Compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if (-not (Test-Path -LiteralPath $Compiler)) {
    throw 'The Windows .NET Framework C# compiler was not found.'
}

$Arguments = @(
    '/nologo',
    '/target:winexe',
    '/platform:x64',
    '/optimize+',
    "/out:$Output",
    '/reference:System.Windows.Forms.dll',
    '/reference:System.Drawing.dll',
    '/reference:System.IO.Compression.dll',
    '/reference:System.IO.Compression.FileSystem.dll',
    "/resource:$(Join-Path $SourceRoot 'yt-seb.cmd'),payload.yt-seb.cmd",
    "/resource:$(Join-Path $SourceRoot 'yt-seb.ps1'),payload.yt-seb.ps1",
    "/resource:$(Join-Path $SourceRoot 'analyze-audio.mjs'),payload.analyze-audio.mjs",
    "/resource:$(Join-Path $SourceRoot 'Resolve-SongMetadata.ps1'),payload.Resolve-SongMetadata.ps1",
    "/resource:$(Join-Path $SourceRoot 'Uninstall-yt-seb.ps1'),payload.Uninstall-yt-seb.ps1",
    (Join-Path $PSScriptRoot 'InstallerSource.cs')
)

& $Compiler @Arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Hash = (Get-FileHash -LiteralPath $Output -Algorithm SHA256).Hash.ToLowerInvariant()
$InstallScript = Join-Path $RepoRoot 'install.ps1'
$InstallContents = Get-Content -LiteralPath $InstallScript -Raw
$InstallContents = $InstallContents -replace '(?m)^\$ExpectedSha256 = ''[0-9a-f]+''\s*$', "`$ExpectedSha256 = '$Hash'"
$InstallContents = $InstallContents.TrimEnd("`r", "`n") + [Environment]::NewLine
[IO.File]::WriteAllText($InstallScript, $InstallContents, [Text.UTF8Encoding]::new($true))

Write-Host "Built: $Output" -ForegroundColor Green
Write-Host "SHA-256: $Hash"
