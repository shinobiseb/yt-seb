$ErrorActionPreference = 'Stop'

$Ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$Ffprobe = (Get-Command ffprobe -ErrorAction Stop).Source
$Folder = Join-Path $env:TEMP ("yt-seb-metadata-test-{0}" -f [guid]::NewGuid())
New-Item -ItemType Directory -Path $Folder | Out-Null

try {
    $Source = Join-Path $Folder 'source.mp3'
    $Tagged = Join-Path $Folder 'tagged.mp3'
    & $Ffmpeg -y -hide_banner -loglevel error -f lavfi `
        -i 'sine=frequency=440:duration=1' -q:a 7 $Source
    if ($LASTEXITCODE -ne 0) { throw 'Could not generate metadata-test audio.' }

    & $Ffmpeg -y -hide_banner -loglevel error -i $Source -map 0:a:0 -c copy `
        -id3v2_version 3 -metadata 'title=Test Song' -metadata 'artist=Test Artist' `
        -metadata 'album=YT-Seb' -metadata 'TBPM=120' -metadata 'TKEY=A minor' `
        -metadata 'comment=Downloaded and analyzed locally with YT-Seb' `
        -metadata 'encoded_by=YT-Seb' $Tagged
    if ($LASTEXITCODE -ne 0) { throw 'Could not create tagged metadata-test audio.' }

    $Probe = (& $Ffprobe -v error -show_entries format_tags -of json $Tagged) | ConvertFrom-Json
    $Tags = $Probe.format.tags
    $Expected = @{
        title = 'Test Song'
        artist = 'Test Artist'
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

