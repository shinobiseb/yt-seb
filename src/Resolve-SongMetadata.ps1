function ConvertTo-MetadataText {
    param([AllowNull()] [object]$Value)

    $Items = @($Value) | ForEach-Object {
        if ($null -ne $_) { ([string]$_).Trim() }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($Items.Count -eq 0) { return $null }
    return ($Items -join ', ')
}

function Remove-VideoTitleDecoration {
    param([AllowNull()] [string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $Clean = $Value.Trim()
    $Decoration = '(?i)\s*[\[(](?:official\s+)?(?:music\s+)?(?:video|audio|lyric(?:s)?|visuali[sz]er)(?:\s+video)?[\])].*$'
    $Clean = ($Clean -replace $Decoration, '').Trim()
    if ([string]::IsNullOrWhiteSpace($Clean)) { return $null }
    return $Clean
}

function Split-ArtistTitle {
    param([AllowNull()] [string]$Value)

    $Clean = Remove-VideoTitleDecoration $Value
    if ([string]::IsNullOrWhiteSpace($Clean)) { return $null }

    # Only explicit, spaced separators are treated as Artist/Title boundaries.
    # Colon and "by" heuristics create false artists for titles such as
    # "Symphony No. 5: Allegro" and "Stand by Me".
    $Patterns = @('^\s*(?<Artist>.+?)\s+(?:-|–|—|\|)\s+(?<Title>.+?)\s*$')
    foreach ($Pattern in $Patterns) {
        $Match = [regex]::Match($Clean, $Pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($Match.Success) {
            $Artist = $Match.Groups['Artist'].Value.Trim()
            $Title = $Match.Groups['Title'].Value.Trim()
            if (-not [string]::IsNullOrWhiteSpace($Artist) -and
                -not [string]::IsNullOrWhiteSpace($Title)) {
                return [pscustomobject]@{ Artist = $Artist; Title = $Title }
            }
        }
    }
    return $null
}

function Split-FeaturedArtistCredit {
    param([AllowNull()] [string]$Value)

    $Clean = Remove-VideoTitleDecoration $Value
    if ([string]::IsNullOrWhiteSpace($Clean)) { return $null }
    $Options = [Text.RegularExpressions.RegexOptions]::IgnoreCase
    $WrappedPattern = '^(?<Before>.*?)\s*[\[(]\s*(?:feat(?:uring)?\.?|ft\.?)\s+(?<Featured>[^\])]+?)\s*[\])]\s*(?<After>.*)$'
    $Match = [regex]::Match($Clean, $WrappedPattern, $Options)
    if ($Match.Success) {
        $Title = (($Match.Groups['Before'].Value.Trim(), $Match.Groups['After'].Value.Trim()) |
            Where-Object { $_ }) -join ' '
        return [pscustomobject]@{
            Title = $Title.Trim()
            Featured = $Match.Groups['Featured'].Value.Trim()
        }
    }

    $TerminalPattern = '^(?<Title>.+?)\s+(?:feat(?:uring)?\.?|ft\.?)\s+(?<Featured>.+?)\s*$'
    $Match = [regex]::Match($Clean, $TerminalPattern, $Options)
    if (-not $Match.Success) { return [pscustomobject]@{ Title = $Clean; Featured = $null } }

    $Title = $Match.Groups['Title'].Value.Trim()
    $Featured = $Match.Groups['Featured'].Value.Trim()
    $QualifierPattern = '^(?<Featured>.+?)\s+(?<Qualifier>[\[(](?:remix|mix|version|edit|remaster(?:ed)?|live|acoustic|radio\s+edit)[\])])$'
    $QualifierMatch = [regex]::Match($Featured, $QualifierPattern, $Options)
    if ($QualifierMatch.Success) {
        $Featured = $QualifierMatch.Groups['Featured'].Value.Trim()
        $Title = "$Title $($QualifierMatch.Groups['Qualifier'].Value)"
    }
    return [pscustomobject]@{
        Title = $Title
        Featured = $Featured
    }
}

function Normalize-ArtistName {
    param([AllowNull()] [string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $Clean = ($Value -replace '\s+', ' ').Trim()
    $Clean = ($Clean -replace '(?i)\s+-\s+Topic$', '').Trim()
    $Clean = ($Clean -replace '(?i)VEVO$', '').Trim()
    $Clean = ($Clean -replace '(?i)\s+Official(?:\s+(?:Artist|Music))?$', '').Trim()
    if ([string]::IsNullOrWhiteSpace($Clean)) { return $null }
    return $Clean
}

function Join-UniqueArtistValues {
    param([AllowNull()] [object[]]$Values)

    $Names = [Collections.Generic.List[string]]::new()
    foreach ($Value in @($Values)) {
        foreach ($Item in @($Value)) {
            $Name = Normalize-ArtistName ([string]$Item)
            if ([string]::IsNullOrWhiteSpace($Name)) { continue }
            $AlreadyPresent = $false
            foreach ($Existing in $Names) {
                if ($Existing.Equals($Name, [StringComparison]::OrdinalIgnoreCase)) {
                    $AlreadyPresent = $true
                    break
                }
            }
            if (-not $AlreadyPresent) { $Names.Add($Name) }
        }
    }
    return ($Names -join ', ')
}

function Resolve-SongMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Metadata,
        [AllowNull()] [string]$SelectedTitle
    )

    $RawTitle = ConvertTo-MetadataText $Metadata.title
    if ([string]::IsNullOrWhiteSpace($RawTitle)) { $RawTitle = ConvertTo-MetadataText $SelectedTitle }

    $Parsed = Split-ArtistTitle $RawTitle
    if ($null -eq $Parsed -and -not [string]::IsNullOrWhiteSpace($SelectedTitle) -and
        $SelectedTitle -cne $RawTitle) {
        $Parsed = Split-ArtistTitle $SelectedTitle
    }

    $Track = ConvertTo-MetadataText $Metadata.track
    $InitialTitle = if (-not [string]::IsNullOrWhiteSpace($Track)) { $Track }
        elseif ($null -ne $Parsed) { $Parsed.Title }
        else { Remove-VideoTitleDecoration $RawTitle }
    $PrimaryCredit = Split-FeaturedArtistCredit $InitialTitle
    $ParsedCredit = if ($null -ne $Parsed) { Split-FeaturedArtistCredit $Parsed.Title } else { $null }
    $SongTitle = if ($null -ne $PrimaryCredit) { $PrimaryCredit.Title } else { $InitialTitle }
    if ([string]::IsNullOrWhiteSpace($SongTitle)) { $SongTitle = 'Unknown Song' }
    $SongTitle = Remove-VideoTitleDecoration $SongTitle
    if ([string]::IsNullOrWhiteSpace($SongTitle)) { $SongTitle = 'Unknown Song' }

    $Artist = Join-UniqueArtistValues @($Metadata.artists)
    $ArtistSource = 'artists'
    if ([string]::IsNullOrWhiteSpace($Artist)) {
        $Artist = Join-UniqueArtistValues @($Metadata.artist)
        $ArtistSource = 'artist'
    }
    if ([string]::IsNullOrWhiteSpace($Artist)) {
        $Artist = Join-UniqueArtistValues @($Metadata.creators)
        $ArtistSource = 'creators'
    }
    if ([string]::IsNullOrWhiteSpace($Artist)) {
        $Artist = Join-UniqueArtistValues @($Metadata.creator)
        $ArtistSource = 'creator'
    }
    if ([string]::IsNullOrWhiteSpace($Artist) -and $null -ne $Parsed) {
        $Artist = Normalize-ArtistName $Parsed.Artist
        $ArtistSource = 'title'
    }
    if ([string]::IsNullOrWhiteSpace($Artist)) {
        $Artist = Normalize-ArtistName (ConvertTo-MetadataText $Metadata.channel)
        $ArtistSource = 'channel'
    }
    if ([string]::IsNullOrWhiteSpace($Artist)) {
        $Artist = Normalize-ArtistName (ConvertTo-MetadataText $Metadata.uploader)
        $ArtistSource = 'uploader'
    }

    $Featured = Join-UniqueArtistValues @(
        $(if ($null -ne $PrimaryCredit) { $PrimaryCredit.Featured }),
        $(if ($null -ne $ParsedCredit) { $ParsedCredit.Featured })
    )
    if (-not [string]::IsNullOrWhiteSpace($Featured)) {
        $Artist = Join-UniqueArtistValues @($Artist, $Featured)
        if ($ArtistSource -notlike '*+featured') { $ArtistSource += '+featured' }
    }

    if ([string]::IsNullOrWhiteSpace($Artist)) {
        $Artist = 'Unknown Artist'
        $ArtistSource = 'fallback'
    }

    return [pscustomobject]@{
        SongTitle = $SongTitle
        Artist = $Artist
        ArtistSource = $ArtistSource
    }
}
