$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$ResolverPath = Join-Path $RepoRoot 'src\Resolve-SongMetadata.ps1'
if (-not (Test-Path -LiteralPath $ResolverPath -PathType Leaf)) {
    throw "Song metadata resolver not found at '$ResolverPath'."
}
. $ResolverPath

$CommandSource = Get-Content -LiteralPath (Join-Path $RepoRoot 'src\yt-seb.ps1') -Raw
foreach ($RequiredArtistTag in @('artist', 'album_artist')) {
    if ($CommandSource -notmatch ([regex]::Escape("$RequiredArtistTag=`$Artist"))) {
        throw "yt-seb.ps1 must write the resolved Artist to the $RequiredArtistTag ID3 field."
    }
}

$Ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$Ffprobe = (Get-Command ffprobe -ErrorAction Stop).Source
$Folder = Join-Path $env:TEMP ("yt-seb-metadata-test-{0}" -f [guid]::NewGuid())
New-Item -ItemType Directory -Path $Folder | Out-Null

try {
    # Use the production resolver's output rather than a disconnected constant.
    # The plural artists field exercises the regression where artist names could
    # previously be lost before the ID3-writing stage.
    $Resolved = Resolve-SongMetadata -Metadata ([pscustomobject]@{
        track = 'Under Pressure'
        title = 'Under Pressure (Official Video)'
        artist = $null
        artists = @('Queen', 'David Bowie')
        creator = $null
        uploader = 'Queen Official'
    }) -SelectedTitle 'Queen & David Bowie - Under Pressure (Official Video)'

    if ($Resolved.Artist -cne 'Queen, David Bowie') {
        throw "Resolver returned artist '$($Resolved.Artist)' instead of 'Queen, David Bowie'."
    }

    $Source = Join-Path $Folder 'source.mp3'
    $Tagged = Join-Path $Folder 'tagged.mp3'
    & $Ffmpeg -y -hide_banner -loglevel error -f lavfi `
        -i 'sine=frequency=440:duration=1' -q:a 7 $Source
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate metadata-test audio.' }

    & $Ffmpeg -y -hide_banner -loglevel error -i $Source -map 0:a:0 -c copy `
        -id3v2_version 3 `
        -metadata "title=$($Resolved.SongTitle)" `
        -metadata "artist=$($Resolved.Artist)" `
        -metadata "album_artist=$($Resolved.Artist)" `
        -metadata 'album=YT-Seb' -metadata 'TBPM=120' -metadata 'TKEY=A minor' `
        -metadata 'comment=Downloaded and analyzed locally with YT-Seb' `
        -metadata 'encoded_by=YT-Seb' $Tagged
    if ($LASTEXITCODE -ne 0) { throw 'Could not create tagged metadata-test audio.' }

    $Probe = (& $Ffprobe -v error -show_entries format_tags -of json $Tagged) | ConvertFrom-Json
    $Tags = $Probe.format.tags
    $Expected = @{
        title = $Resolved.SongTitle
        artist = $Resolved.Artist
        album_artist = $Resolved.Artist
        album = 'YT-Seb'
        TBPM = '120'
        TKEY = 'A minor'
        comment = 'Downloaded and analyzed locally with YT-Seb'
        encoded_by = 'YT-Seb'
    }
    foreach ($Name in $Expected.Keys) {
        if ($Tags.$Name -ne $Expected[$Name]) {
            throw "Metadata field $Name was '$($Tags.$Name)' instead of '$($Expected[$Name])'."
        }
    }
    Write-Host 'Metadata test passed.' -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $Folder -Recurse -Force -ErrorAction SilentlyContinue
}
