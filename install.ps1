$ErrorActionPreference = 'Stop'

$SetupUrl = 'https://raw.githubusercontent.com/shinobiseb/yt-seb/main/dist/yt-seb%20Setup.exe'
$ExpectedSha256 = '235cefead2b7002920dbfb215e0fdc9554a2df8c3e7a510b03171b79da14e3d6'
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



