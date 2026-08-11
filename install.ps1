$ErrorActionPreference = 'Stop'

$SetupUrl = 'https://raw.githubusercontent.com/shinobiseb/yt-seb/development/dist/yt-seb%20Setup.exe'
$ExpectedSha256 = 'e5590ddff0b2845a09eff686e9cbd84538adcc2f1cd38ca30b4d69d480d1f229'
$SetupPath = Join-Path $env:TEMP ("yt-seb-Setup-{0}.exe" -f [guid]::NewGuid())

try {
    Write-Host 'Downloading yt-seb Setup from GitHub...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $SetupUrl -OutFile $SetupPath -UseBasicParsing

    $ActualSha256 = (Get-FileHash -LiteralPath $SetupPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ActualSha256 -ne $ExpectedSha256) {
        throw "Setup checksum verification failed. Expected $ExpectedSha256 but received $ActualSha256."
    }

    Write-Host 'Checksum verified. Opening the consent-based installer...' -ForegroundColor Green
    $Process = Start-Process -FilePath $SetupPath -PassThru
    $Process.WaitForExit()
}
finally {
    Remove-Item -LiteralPath $SetupPath -Force -ErrorAction SilentlyContinue
}




