param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$QueryParts
)

$ErrorActionPreference = 'Stop'
$DownloadFolder = Join-Path $env:USERPROFILE 'Music'
$SearchResultCount = 5

function Fail([string]$Message) {
    Write-Host "Error: $Message" -ForegroundColor Red
    exit 1
}

if (-not $QueryParts -or [string]::IsNullOrWhiteSpace(($QueryParts -join ' '))) {
    Write-Host 'Usage: yt-seb <song title>' -ForegroundColor Yellow
    Write-Host 'Example: yt-seb september earth wind and fire'
    exit 2
}

$Query = ($QueryParts -join ' ').Trim()
$YtDlp = Join-Path $PSScriptRoot 'yt-dlp.exe'
$Ffmpeg = Join-Path $PSScriptRoot 'ffmpeg.exe'
$Deno = Join-Path $PSScriptRoot 'deno.exe'

foreach ($RequiredFile in @($YtDlp, $Ffmpeg, $Deno)) {
    if (-not (Test-Path -LiteralPath $RequiredFile)) {
        Fail "Required installed file is missing: $RequiredFile. Run yt-seb Setup again."
    }
}

if (-not (Test-Path -LiteralPath $DownloadFolder)) {
    New-Item -ItemType Directory -Path $DownloadFolder -Force | Out-Null
}

Write-Host "Searching YouTube for: $Query" -ForegroundColor Cyan

try {
    $RuntimeArgs = @('--js-runtimes', "deno:$Deno")
    $SearchSpec = "ytsearch${SearchResultCount}:$Query"
    $SearchJson = & $YtDlp `
        @RuntimeArgs `
        --flat-playlist `
        --dump-single-json `
        --skip-download `
        --no-warnings `
        --ignore-errors `
        $SearchSpec

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($SearchJson -join ''))) {
        throw 'The YouTube search failed.'
    }

    $SearchData = ($SearchJson -join "`n") | ConvertFrom-Json
    $Candidates = @($SearchData.entries) | Where-Object {
        $null -ne $_ -and ($_.id -or $_.webpage_url -or $_.url)
    }

    if ($Candidates.Count -eq 0) { throw 'No usable videos were found.' }

    # YouTube supplies relevance-ranked results; choose the first usable item
    # from the top five without re-ranking by popularity.
    $Selected = $Candidates | Select-Object -First 1

    if ($Selected.webpage_url -match '^https?://') {
        $VideoUrl = $Selected.webpage_url
    }
    elseif ($Selected.url -match '^https?://') {
        $VideoUrl = $Selected.url
    }
    else {
        $VideoUrl = "https://www.youtube.com/watch?v=$($Selected.id)"
    }

    try { Set-Clipboard -Value $VideoUrl } catch { }

    Write-Host "Selected: $($Selected.title)" -ForegroundColor Green
    Write-Host "URL:      $VideoUrl"
    Write-Host "Saving to $DownloadFolder ..." -ForegroundColor Cyan

    & $YtDlp `
        @RuntimeArgs `
        --ffmpeg-location $Ffmpeg `
        -x `
        --audio-format mp3 `
        -P $DownloadFolder `
        --no-playlist `
        --windows-filenames `
        $VideoUrl

    if ($LASTEXITCODE -ne 0) {
        throw "yt-dlp ended with exit code $LASTEXITCODE."
    }

    Write-Host 'File downloaded!' -ForegroundColor Green
    exit 0
}
catch {
    Fail $_.Exception.Message
}

