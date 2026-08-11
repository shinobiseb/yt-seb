$ErrorActionPreference = 'Stop'

$SetupUrl = 'https://raw.githubusercontent.com/shinobiseb/yt-seb/development/dist/yt-seb%20Setup.exe'
$ExpectedSha256 = '6989fd547e0b5e3c963c88930bb6a314b4204d7cfcebe876e90b9b94652ba81a'
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
