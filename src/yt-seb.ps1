param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = 'Stop'
$DownloadFolder = Join-Path $env:USERPROFILE 'Music'
$SearchResultCount = 5

function Fail([string]$Message) {
    Write-Host "Error: $Message" -ForegroundColor Red
    exit 1
}

function Get-SafeFileComponent([string]$Value, [int]$MaximumLength = 70) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'Unknown' }
    $Safe = $Value -replace '[<>:"/\\|?*\x00-\x1F]', '-'
    $Safe = ($Safe -replace '\s+', ' ').Trim().TrimEnd('.')
    if ($Safe.Length -gt $MaximumLength) { $Safe = $Safe.Substring(0, $MaximumLength).Trim() }
    if ([string]::IsNullOrWhiteSpace($Safe)) { return 'Unknown' }
    return $Safe
}

function Get-AvailablePath([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $Directory = Split-Path $Path -Parent
    $BaseName = [IO.Path]::GetFileNameWithoutExtension($Path)
    $Extension = [IO.Path]::GetExtension($Path)
    for ($Index = 2; $Index -lt 10000; $Index++) {
        $Candidate = Join-Path $Directory "$BaseName ($Index)$Extension"
        if (-not (Test-Path -LiteralPath $Candidate)) { return $Candidate }
    }
    throw 'Could not create a unique output filename.'
}

$SongInfo = $false
$QueryParts = @()
foreach ($Argument in @($Arguments)) {
    if ($Argument -ieq '-si') { $SongInfo = $true }
    else { $QueryParts += $Argument }
}

if (-not $QueryParts -or [string]::IsNullOrWhiteSpace(($QueryParts -join ' '))) {
    Write-Host 'Usage: yt-seb [-si] <song title>' -ForegroundColor Yellow
    Write-Host 'Example: yt-seb september earth wind and fire'
    Write-Host 'Song info: yt-seb -si september earth wind and fire'
    exit 2
}

$Query = ($QueryParts -join ' ').Trim()
$YtDlp = Join-Path $PSScriptRoot 'yt-dlp.exe'
$Ffmpeg = Join-Path $PSScriptRoot 'ffmpeg.exe'
$Deno = Join-Path $PSScriptRoot 'deno.exe'
$Analyzer = Join-Path $PSScriptRoot 'analyze-audio.mjs'

foreach ($RequiredFile in @($YtDlp, $Ffmpeg, $Deno)) {
    if (-not (Test-Path -LiteralPath $RequiredFile)) {
        Fail "Required installed file is missing: $RequiredFile. Run yt-seb Setup again."
    }
}
if ($SongInfo -and -not (Test-Path -LiteralPath $Analyzer)) {
    Fail "The song-analysis file is missing: $Analyzer. Run yt-seb Setup again."
}

if (-not (Test-Path -LiteralPath $DownloadFolder)) {
    New-Item -ItemType Directory -Path $DownloadFolder -Force | Out-Null
}

Write-Host "Searching YouTube for: $Query" -ForegroundColor Cyan
$WorkFolder = $null

try {
    $RuntimeArgs = @('--js-runtimes', "deno:$Deno")
    $SearchSpec = "ytsearch${SearchResultCount}:$Query"
    $SearchJson = & $YtDlp @RuntimeArgs --flat-playlist --dump-single-json `
        --skip-download --no-warnings --ignore-errors $SearchSpec

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

    if (-not $SongInfo) {
        Write-Host "Saving to $DownloadFolder ..." -ForegroundColor Cyan
        & $YtDlp @RuntimeArgs --ffmpeg-location $Ffmpeg -x --audio-format mp3 `
            -P $DownloadFolder --no-playlist --windows-filenames $VideoUrl
        if ($LASTEXITCODE -ne 0) { throw "yt-dlp ended with exit code $LASTEXITCODE." }
        Write-Host 'File downloaded!' -ForegroundColor Green
        exit 0
    }

    Write-Host 'Reading song metadata...' -ForegroundColor Cyan
    $MetadataJson = & $YtDlp @RuntimeArgs --dump-single-json --skip-download `
        --no-warnings --no-playlist $VideoUrl
    if ($LASTEXITCODE -ne 0) { throw 'Could not read full video metadata.' }
    $Metadata = ($MetadataJson -join "`n") | ConvertFrom-Json

    $SongTitle = if ($Metadata.track) { [string]$Metadata.track } else { [string]$Metadata.title }
    $Artist = if ($Metadata.artist) { [string]$Metadata.artist }
        elseif ($Metadata.creator) { [string]$Metadata.creator }
        else { [string]$Metadata.uploader }

    if (-not $Metadata.track -and $SongTitle -match '^\s*(.+?)\s+-\s+(.+?)\s*$') {
        if (-not $Metadata.artist) { $Artist = $Matches[1] }
        $SongTitle = $Matches[2]
    }
    $SongTitle = ($SongTitle -replace '(?i)\s*[\[(](official\s+)?(music\s+)?(video|audio|lyric(s)?)[\])].*$', '').Trim()
    if ([string]::IsNullOrWhiteSpace($SongTitle)) { $SongTitle = [string]$Selected.title }
    if ([string]::IsNullOrWhiteSpace($Artist)) { $Artist = 'Unknown Artist' }

    $WorkFolder = Join-Path ([IO.Path]::GetTempPath()) ("yt-seb-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $WorkFolder -Force | Out-Null
    $Template = Join-Path $WorkFolder 'source.%(ext)s'
    Write-Host 'Downloading audio for analysis...' -ForegroundColor Cyan
    & $YtDlp @RuntimeArgs --ffmpeg-location $Ffmpeg -x --audio-format mp3 `
        --no-playlist --windows-filenames -o $Template $VideoUrl
    if ($LASTEXITCODE -ne 0) { throw "yt-dlp ended with exit code $LASTEXITCODE." }

    $SourceMp3 = Join-Path $WorkFolder 'source.mp3'
    if (-not (Test-Path -LiteralPath $SourceMp3)) { throw 'The temporary MP3 was not created.' }

    $PcmPath = Join-Path $WorkFolder 'analysis.f32le'
    Write-Host 'Estimating tempo and musical key locally...' -ForegroundColor Cyan
    & $Ffmpeg -y -hide_banner -loglevel error -i $SourceMp3 -ac 1 -ar 11025 -f f32le $PcmPath
    if ($LASTEXITCODE -ne 0) { throw 'FFmpeg could not prepare audio for analysis.' }

    $AnalysisJson = & $Deno run --quiet "--allow-read=$PSScriptRoot,$WorkFolder" `
        $Analyzer $PcmPath 11025
    if ($LASTEXITCODE -ne 0) { throw 'Local tempo/key analysis failed.' }
    $Analysis = ($AnalysisJson -join "`n") | ConvertFrom-Json
    $Tempo = [int]$Analysis.tempo
    $Key = [string]$Analysis.key
    if ($Tempo -lt 30 -or [string]::IsNullOrWhiteSpace($Key)) {
        throw 'Audio analysis returned invalid results.'
    }

    $SafeTitle = Get-SafeFileComponent $SongTitle 70
    $SafeArtist = Get-SafeFileComponent $Artist 55
    # ASCII | is forbidden in Windows filenames; U+2502 is a safe visual equivalent.
    $FileName = "$SafeTitle │ $SafeArtist │ $Tempo BPM │ $Key │ [YT-Seb].mp3"
    $FinalPath = Get-AvailablePath (Join-Path $DownloadFolder $FileName)

    Write-Host 'Writing ID3 metadata...' -ForegroundColor Cyan
    $TagArguments = @(
        '-y', '-hide_banner', '-loglevel', 'error', '-i', $SourceMp3,
        '-map', '0:a:0', '-c', 'copy', '-id3v2_version', '3',
        '-metadata', "title=$SongTitle",
        '-metadata', "artist=$Artist",
        '-metadata', 'album=YT-Seb',
        '-metadata', "TBPM=$Tempo",
        '-metadata', "TKEY=$Key",
        '-metadata', 'comment=Downloaded and analyzed locally with YT-Seb',
        '-metadata', 'encoded_by=YT-Seb',
        $FinalPath
    )
    & $Ffmpeg @TagArguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $FinalPath)) {
        throw 'FFmpeg could not write the final tagged MP3.'
    }

    Write-Host "Tempo: $Tempo BPM" -ForegroundColor Green
    Write-Host "Key:   $Key" -ForegroundColor Green
    Write-Host "Saved: $FinalPath" -ForegroundColor Green
    exit 0
}
catch {
    Fail $_.Exception.Message
}
finally {
    if ($WorkFolder -and (Test-Path -LiteralPath $WorkFolder)) {
        Remove-Item -LiteralPath $WorkFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

