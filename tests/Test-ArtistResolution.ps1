param(
    [string]$ResolverPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Resolve-SongMetadata.ps1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ResolverPath -PathType Leaf)) {
    throw @"
Artist/title resolver not found at '$ResolverPath'.
Extract the metadata-selection logic into src\Resolve-SongMetadata.ps1 and expose:

    Resolve-SongMetadata -Metadata <pscustomobject> -SelectedTitle <string>

The function must return an object with non-empty SongTitle and Artist properties.
"@
}

. $ResolverPath

if (-not (Get-Command Resolve-SongMetadata -CommandType Function -ErrorAction SilentlyContinue)) {
    throw "'$ResolverPath' must define a Resolve-SongMetadata function."
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)] [string]$Case,
        [Parameter(Mandatory)] [string]$Property,
        [AllowNull()] [object]$Actual,
        [AllowNull()] [object]$Expected
    )

    if ([string]$Actual -cne [string]$Expected) {
        throw "[$Case] Expected $Property '$Expected', got '$Actual'."
    }
}

$Cases = @(
    @{
        Name = 'native track and artist win'
        Metadata = [pscustomobject]@{
            track = 'One More Time'
            artist = 'Daft Punk'
            title = 'Daft Punk - One More Time (Official Video)'
            creator = 'Daft Punk'
            uploader = 'Daft Punk'
        }
        SelectedTitle = 'Daft Punk - One More Time (Official Video)'
        ExpectedTitle = 'One More Time'
        ExpectedArtist = 'Daft Punk'
    },
    @{
        # Regression: the old inline implementation parsed "Artist - Title"
        # only when track was absent, leaving artist missing in this common case.
        Name = 'title supplies artist when track exists but artist is absent'
        Metadata = [pscustomobject]@{
            track = 'One More Time'
            artist = $null
            title = 'Daft Punk - One More Time (Official Video)'
            creator = $null
            uploader = $null
        }
        SelectedTitle = 'Daft Punk - One More Time (Official Video)'
        ExpectedTitle = 'One More Time'
        ExpectedArtist = 'Daft Punk'
    },
    @{
        Name = 'Unicode en dash separates artist and title'
        Metadata = [pscustomobject]@{
            track = $null
            artist = $null
            title = 'Fleetwood Mac – Dreams (Official Music Video)'
            creator = $null
            uploader = 'Fleetwood Mac'
        }
        SelectedTitle = 'Fleetwood Mac – Dreams (Official Music Video)'
        ExpectedTitle = 'Dreams'
        ExpectedArtist = 'Fleetwood Mac'
    },
    @{
        Name = 'creator is preferred to uploader when title has no artist'
        Metadata = [pscustomobject]@{
            track = 'Teardrop'
            artist = $null
            title = 'Teardrop (Official Audio)'
            creator = 'Massive Attack'
            uploader = 'MassiveAttackVEVO'
        }
        SelectedTitle = 'Teardrop (Official Audio)'
        ExpectedTitle = 'Teardrop'
        ExpectedArtist = 'Massive Attack'
    },
    @{
        Name = 'artists collection fills singular artist metadata gap'
        Metadata = [pscustomobject]@{
            track = 'Under Pressure'
            artist = $null
            artists = @('Queen', 'David Bowie')
            title = 'Under Pressure (Official Video)'
            creator = $null
            uploader = 'Queen Official'
        }
        SelectedTitle = 'Under Pressure (Official Video)'
        ExpectedTitle = 'Under Pressure'
        ExpectedArtist = 'Queen, David Bowie'
    },
    @{
        Name = 'Topic suffix is removed from uploader fallback'
        Metadata = [pscustomobject]@{
            track = 'Fast Car'
            artist = $null
            title = 'Fast Car'
            creator = $null
            uploader = 'Tracy Chapman - Topic'
        }
        SelectedTitle = 'Fast Car'
        ExpectedTitle = 'Fast Car'
        ExpectedArtist = 'Tracy Chapman'
    },
    @{
        Name = 'selected search title fills missing full metadata title'
        Metadata = [pscustomobject]@{
            track = $null
            artist = $null
            title = $null
            creator = $null
            uploader = 'Sade'
        }
        SelectedTitle = 'Sade - Smooth Operator (Official Video)'
        ExpectedTitle = 'Smooth Operator'
        ExpectedArtist = 'Sade'
    },
    @{
        Name = 'unknown artist is explicit and never blank'
        Metadata = [pscustomobject]@{
            track = 'Orphan Song'
            artist = '   '
            title = 'Orphan Song (Official Audio)'
            creator = '   '
            uploader = '   '
        }
        SelectedTitle = 'Orphan Song (Official Audio)'
        ExpectedTitle = 'Orphan Song'
        ExpectedArtist = 'Unknown Artist'
    },
    @{
        # Mirrors the live result that originally exposed featured artists
        # disappearing when yt-dlp supplied a plain track and primary artist.
        Name = 'live Omen 48 Laws result includes Donnie Trumpet credit'
        Metadata = [pscustomobject]@{
            track = '48 Laws'
            artist = 'Omen'
            artists = @('Omen')
            title = 'Omen - 48 Laws ft. Donnie Trumpet'
            creator = $null
            uploader = 'OmenVEVO'
        }
        SelectedTitle = 'Omen - 48 Laws ft. Donnie Trumpet'
        ExpectedTitle = '48 Laws'
        ExpectedArtist = 'Omen, Donnie Trumpet'
    },
    @{
        Name = 'en dash title retains featured artist credit'
        Metadata = [pscustomobject]@{
            track = $null
            artist = $null
            title = 'SZA – Snooze feat. Justin Bieber (Official Video)'
            creator = $null
            uploader = 'SZA'
        }
        SelectedTitle = 'SZA – Snooze feat. Justin Bieber (Official Video)'
        ExpectedTitle = 'Snooze'
        ExpectedArtist = 'SZA, Justin Bieber'
    },
    @{
        Name = 'em dash title supports parenthesized featured artist credit'
        Metadata = [pscustomobject]@{
            track = $null
            artist = $null
            title = 'Beyoncé — Crazy in Love (feat. Jay-Z) (Official Video)'
            creator = $null
            uploader = 'Beyoncé'
        }
        SelectedTitle = 'Beyoncé — Crazy in Love (feat. Jay-Z) (Official Video)'
        ExpectedTitle = 'Crazy in Love'
        ExpectedArtist = 'Beyoncé, Jay-Z'
    },
    @{
        Name = 'plural creators are retained when artist fields are absent'
        Metadata = [pscustomobject]@{
            track = 'Leave the Door Open'
            artist = $null
            artists = @()
            title = 'Leave the Door Open (Official Video)'
            creators = @('Bruno Mars', 'Anderson .Paak', 'Silk Sonic')
            creator = $null
            uploader = 'Bruno Mars'
        }
        SelectedTitle = 'Leave the Door Open (Official Video)'
        ExpectedTitle = 'Leave the Door Open'
        ExpectedArtist = 'Bruno Mars, Anderson .Paak, Silk Sonic'
    },
    @{
        Name = 'whitespace plural field falls through to singular artist'
        Metadata = [pscustomobject]@{
            track = 'Good Days'
            artist = '  SZA  '
            artists = @(' ', "`t")
            title = 'Good Days (Official Audio)'
            creator = 'Wrong fallback'
            uploader = 'Wrong uploader'
        }
        SelectedTitle = 'Good Days (Official Audio)'
        ExpectedTitle = 'Good Days'
        ExpectedArtist = 'SZA'
    },
    @{
        Name = 'duplicate featured artist is deduplicated case-insensitively'
        Metadata = [pscustomobject]@{
            track = '48 Laws'
            artist = 'Omen'
            title = 'Omen - 48 Laws feat. omen'
            creator = $null
            uploader = 'Omen'
        }
        SelectedTitle = 'Omen - 48 Laws feat. omen'
        ExpectedTitle = '48 Laws'
        ExpectedArtist = 'Omen'
    },
    @{
        Name = 'hyphen in blink-182 is not treated as title separator'
        Metadata = [pscustomobject]@{
            track = $null
            artist = $null
            title = 'blink-182 - All the Small Things (Official Video)'
            creator = $null
            uploader = $null
        }
        SelectedTitle = 'blink-182 - All the Small Things (Official Video)'
        ExpectedTitle = 'All the Small Things'
        ExpectedArtist = 'blink-182'
    },
    @{
        Name = 'commas and ampersand in Earth Wind and Fire remain one artist'
        Metadata = [pscustomobject]@{
            track = $null
            artist = $null
            title = 'Earth, Wind & Fire - September (Official Video)'
            creator = $null
            uploader = $null
        }
        SelectedTitle = 'Earth, Wind & Fire - September (Official Video)'
        ExpectedTitle = 'September'
        ExpectedArtist = 'Earth, Wind & Fire'
    },
    @{
        Name = 'Stand by Me is a title and does not create artist Me'
        Metadata = [pscustomobject]@{
            track = $null
            artist = $null
            title = 'Stand by Me'
            creator = $null
            channel = 'Ben E. King'
            uploader = 'Ben E. King'
        }
        SelectedTitle = 'Stand by Me'
        ExpectedTitle = 'Stand by Me'
        ExpectedArtist = 'Ben E. King'
    },
    @{
        Name = 'classical movement colon does not make symphony an artist'
        Metadata = [pscustomobject]@{
            track = $null
            artist = $null
            title = 'Symphony No. 5: I. Allegro'
            creator = $null
            channel = 'London Symphony Orchestra'
            uploader = 'London Symphony Orchestra'
        }
        SelectedTitle = 'Symphony No. 5: I. Allegro'
        ExpectedTitle = 'Symphony No. 5: I. Allegro'
        ExpectedArtist = 'London Symphony Orchestra'
    },
    @{
        Name = 'Live colon prefix remains part of title'
        Metadata = [pscustomobject]@{
            track = $null
            artist = $null
            title = 'Live: Comfortably Numb'
            creator = $null
            channel = 'Pink Floyd'
            uploader = 'Pink Floyd'
        }
        SelectedTitle = 'Live: Comfortably Numb'
        ExpectedTitle = 'Live: Comfortably Numb'
        ExpectedArtist = 'Pink Floyd'
    },
    @{
        Name = 'wrapped feature is removed without discarding trailing remix label'
        Metadata = [pscustomobject]@{
            track = 'Song (feat. Guest) [Remix]'
            artist = 'Base Artist'
            title = 'Base Artist - Song (feat. Guest) [Remix]'
            creator = $null
            channel = 'Base Artist'
            uploader = 'Base Artist'
        }
        SelectedTitle = 'Base Artist - Song (feat. Guest) [Remix]'
        ExpectedTitle = 'Song [Remix]'
        ExpectedArtist = 'Base Artist, Guest'
    },
    @{
        Name = 'Official channel suffix is removed from artist fallback'
        Metadata = [pscustomobject]@{
            track = 'Bohemian Rhapsody'
            artist = $null
            title = 'Bohemian Rhapsody (Official Video)'
            creator = $null
            channel = 'Queen Official'
            uploader = 'Queen Official'
        }
        SelectedTitle = 'Bohemian Rhapsody (Official Video)'
        ExpectedTitle = 'Bohemian Rhapsody'
        ExpectedArtist = 'Queen'
    },
    @{
        Name = 'unwrapped feature is removed without consuming trailing remix label'
        Metadata = [pscustomobject]@{
            track = $null
            artist = $null
            title = 'Artist - Song feat. Guest (Remix)'
            creator = $null
            channel = 'Artist'
            uploader = 'Artist'
        }
        SelectedTitle = 'Artist - Song feat. Guest (Remix)'
        ExpectedTitle = 'Song (Remix)'
        ExpectedArtist = 'Artist, Guest'
    }
)

$Passed = 0
foreach ($TestCase in $Cases) {
    $Result = Resolve-SongMetadata `
        -Metadata $TestCase.Metadata `
        -SelectedTitle $TestCase.SelectedTitle

    if ($null -eq $Result) {
        throw "[$($TestCase.Name)] Resolver returned null."
    }

    Assert-Equal -Case $TestCase.Name -Property 'SongTitle' `
        -Actual $Result.SongTitle -Expected $TestCase.ExpectedTitle
    Assert-Equal -Case $TestCase.Name -Property 'Artist' `
        -Actual $Result.Artist -Expected $TestCase.ExpectedArtist
    $Passed++
}

Write-Host "Artist-resolution tests passed ($Passed/$($Cases.Count))." -ForegroundColor Green
