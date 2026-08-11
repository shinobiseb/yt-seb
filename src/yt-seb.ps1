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

function Find-ToolPath {
    param(
        [Parameter(Mandatory)] [string]$LocalName,
        [Parameter(Mandatory)] [string[]]$CommandNames
    )

    $LocalPath = Join-Path $PSScriptRoot $LocalName
    if (Test-Path -LiteralPath $LocalPath -PathType Leaf) { return $LocalPath }
    foreach ($CommandName in $CommandNames) {
        $Command = Get-Command $CommandName -ErrorAction SilentlyContinue
        if ($Command) { return $Command.Source }
    }
    return $null
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
$YtDlp = Find-ToolPath -LocalName 'yt-dlp.exe' -CommandNames @('yt-dlp.exe', 'yt-dlp')
$Ffmpeg = Find-ToolPath -LocalName 'ffmpeg.exe' -CommandNames @('ffmpeg.exe', 'ffmpeg')
$Deno = Find-ToolPath -LocalName 'deno.exe' -CommandNames @('deno.exe', 'deno')
$Node = Find-ToolPath -LocalName 'node.exe' -CommandNames @('node.exe', 'node')
$Analyzer = Join-Path $PSScriptRoot 'analyze-audio.mjs'
$MetadataResolver = Join-Path $PSScriptRoot 'Resolve-SongMetadata.ps1'

if (-not $YtDlp) { Fail 'yt-dlp was not found. Run yt-seb Setup again.' }
if (-not $Ffmpeg) { Fail 'FFmpeg was not found. Run yt-seb Setup again.' }
if (-not $Deno -and -not $Node) { Fail 'Neither Deno nor Node.js was found for YouTube processing.' }
foreach ($SongInfoFile in @($Analyzer, $MetadataResolver)) {
    if ($SongInfo -and -not (Test-Path -LiteralPath $SongInfoFile)) {
        Fail "The song-information file is missing: $SongInfoFile. Run yt-seb Setup again."
    }
}
if ($SongInfo) { . $MetadataResolver }

if (-not (Test-Path -LiteralPath $DownloadFolder)) {
    New-Item -ItemType Directory -Path $DownloadFolder -Force | Out-Null
}

Write-Host "Searching YouTube for: $Query" -ForegroundColor Cyan
$WorkFolder = $null

try {
    $RuntimeArgs = if ($Deno) { @('--js-runtimes', "deno:$Deno") }
        else { @('--js-runtimes', "node:$Node") }
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

    $ResolvedMetadata = Resolve-SongMetadata -Metadata $Metadata -SelectedTitle ([string]$Selected.title)
    $SongTitle = $ResolvedMetadata.SongTitle
    $Artist = $ResolvedMetadata.Artist
    Write-Host "Title:  $SongTitle"
    Write-Host "Artist: $Artist (source: $($ResolvedMetadata.ArtistSource))"

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

    if ($Deno) {
        $AnalysisJson = & $Deno run --quiet "--allow-read=$PSScriptRoot,$WorkFolder" `
            $Analyzer $PcmPath 11025
    }
    else {
        $AnalysisJson = & $Node $Analyzer $PcmPath 11025
    }
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
        '-metadata', "album_artist=$Artist",
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
