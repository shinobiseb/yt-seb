# Artist metadata and `-si` behavior

This document describes the experimental song-information workflow on the
`development` branch, including the missing-artist fix introduced in commit
`c7f5be2`.

## Command

```powershell
yt-seb -si song title
```

The command searches the first five YouTube results in YouTube relevance order,
selects the first usable result, downloads its audio, estimates tempo and key
locally, writes ID3 metadata, and saves the MP3 in the current user's Music
folder.

## Output filename

```text
Song Title │ Artist │ 120 BPM │ A minor │ [YT-Seb].mp3
```

Windows does not allow ASCII `|` in a filename. The visually similar Unicode
box-drawing character `│` is used instead. Characters forbidden by Windows are
replaced in title and artist filename components, and an incrementing suffix is
added rather than overwriting an existing file.

## Artist resolution

YouTube and yt-dlp do not provide artist information in one consistent field.
yt-seb selects the first non-empty source in this order:

1. Canonical `artists[]`, joined and case-insensitively deduplicated.
2. Legacy singular `artist`.
3. Canonical `creators[]`.
4. Legacy singular `creator`.
5. An explicit `Artist - Song`, `Artist – Song`, or `Artist — Song` video-title
   boundary.
6. The cleaned YouTube channel name.
7. The cleaned uploader name.
8. `Unknown Artist` when no responsible attribution can be established.

Whitespace-only fields are ignored. Exact ` - Topic`, `VEVO`, and trailing
`Official`, `Official Artist`, or `Official Music` channel decorations are
removed from fallback names.

Colon and general `Song by Artist` guessing are intentionally not used. Those
heuristics create false artists from legitimate titles such as `Stand by Me`,
`Symphony No. 5: I. Allegro`, and `Live: Comfortably Numb`.

## Featured artists

Terminal `ft.`, `feat.`, and `featuring` credits are moved from the song title
into the Artist value and deduplicated against structured artists.

Example:

```text
YouTube title: Omen - 48 Laws ft. Donnie Trumpet
Song title:    48 Laws
Artist:        Omen, Donnie Trumpet
```

Wrapped credits and version qualifiers are kept separate:

```text
Input:   Artist - Song feat. Guest (Remix)
Title:   Song (Remix)
Artist:  Artist, Guest
```

Internal hyphens and commas remain intact. Examples include `blink-182` and
`Earth, Wind & Fire`.

## Written ID3 fields

The final MP3 contains:

| ID3 value | Contents |
| --- | --- |
| `title` | Resolved song title |
| `artist` | Resolved primary and featured artists |
| `album_artist` | Same resolved artist value for players that prefer album artist |
| `album` | `YT-Seb` |
| `TBPM` | Locally estimated tempo |
| `TKEY` | Locally estimated musical key |
| `comment` | `Downloaded and analyzed locally with YT-Seb` |
| `encoded_by` | `YT-Seb` |

Tempo and key are estimates, not authoritative catalog data. The analyzer uses
up to two minutes of mono PCM locally. It does not upload song audio to an
analysis service. Half-time/double-time rhythm, key changes, live performances,
and noisy recordings can reduce accuracy.

## Runtime selection

yt-seb prefers private tools installed beside the command. It can fall back to
tools on `PATH`:

- yt-dlp: local executable, then `yt-dlp` on `PATH`;
- FFmpeg: local executable, then `ffmpeg` on `PATH`;
- JavaScript runtime: Deno when available, otherwise Node.js.

The installer supplies private yt-dlp, FFmpeg, and Deno copies. Node.js fallback
supports existing/manual installations.

## Troubleshooting command selection

If `-si` behaves like ordinary search text or the resolver file is reported
missing, inspect every command Windows can find:

```powershell
Get-Command yt-seb -All | Select-Object Name, Source
```

The intended installer location is:

```text
%LOCALAPPDATA%\Programs\yt-seb
```

An older `yt-seb.ps1` or `yt-seb.cmd` earlier on `PATH` can shadow the installed
development command. Remove or rename the older wrapper, or move
`%LOCALAPPDATA%\Programs\yt-seb` earlier in the user PATH, then open a new
terminal. Reinstalling alone does not necessarily change the order of existing
PATH entries.

The repository smoke test can enforce the expected installed location:

```powershell
.\tests\Test-CommandResolution.ps1 -RequireInstalledCommand
```

## Validation performed for the fix

- 22 artist-resolution regression and adversarial cases.
- PowerShell 7 and Windows PowerShell 5.1 execution.
- Live YouTube metadata checks, including the Omen/Donnie Trumpet regression.
- Resolved multi-artist ID3 and album-artist round-trip through FFmpeg/ffprobe.
- Synthetic local tempo/key analysis (`118 BPM`, `A minor`).
- Installer payload/resource verification.
- Installer SHA-256 agreement with the value pinned in `install.ps1`.
- Active-command path and source-hash smoke testing.

The installer binary associated with this fix has SHA-256:

```text
6989fd547e0b5e3c963c88930bb6a314b4204d7cfcebe876e90b9b94652ba81a
```

The pinned value in `install.ps1` is the source of truth after future installer
rebuilds.
