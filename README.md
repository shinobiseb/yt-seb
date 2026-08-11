# yt-seb — development branch

`yt-seb` is a Windows and macOS command-line YouTube song downloader. Enter a song title
and it searches YouTube's top five relevance-ranked results, selects the first
usable result, copies its URL to the clipboard, and saves MP3 audio in your
Music folder.

## Install the development build on Windows

Open PowerShell and run:

```powershell
$p=Join-Path $env:TEMP 'yt-seb-install.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/shinobiseb/yt-seb/development/install.ps1' -OutFile $p; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p
```

This command downloads the repository's [`install.ps1`](install.ps1) to a
temporary file. That script downloads `dist/yt-seb Setup.exe`, verifies its
pinned SHA-256 checksum, and opens it. Setup does not install anything until you
read the disclosure and click **I Agree**. It installs only for the current
Windows user and does not request administrator privileges.

You may instead download the repository and run `dist/yt-seb Setup.exe`
manually.

## Install the development build on macOS

The macOS build supports Apple silicon and Intel Macs, installs per-user without
`sudo`, and presents an explicit **I Agree** confirmation dialog. See the
[macOS installation and usage guide](mac/README.md).

## Use

Open a **new** Command Prompt or PowerShell window after installation:

```powershell
yt-seb song title
```

Example:

```powershell
yt-seb september earth wind and fire
```

The selected link is copied to the clipboard and the MP3 is saved under your
Windows Music folder.

## Experimental song information mode

Use `-si` to estimate tempo and musical key locally and write song metadata:

```powershell
yt-seb -si september earth wind and fire
```

The resulting MP3 is named using this layout:

```text
Song Title │ Artist │ 120 BPM │ Found Key │ [YT-Seb].mp3
```

Windows forbids the ASCII pipe character (`|`) in filenames, so yt-seb uses the
visually equivalent Unicode separator `│`. The MP3 receives ID3 title, artist,
album artist, album (`YT-Seb`), tempo, initial-key, comment, and encoder
metadata.

Tempo and key are estimates derived from up to two minutes of the downloaded
audio. Half-time/double-time rhythm, key changes, live recordings, or noisy
audio can produce imperfect results. No song audio is uploaded to an analysis
service.

Artist attribution is resolved from structured yt-dlp metadata, decorated video
titles, and cleaned channel fallbacks. Featured credits such as `ft.`, `feat.`,
and `featuring` are moved into the Artist tag and removed from the song title.
See [Artist metadata and `-si` behavior](docs/ARTIST-METADATA.md) for resolution
rules, examples, validation, and troubleshooting.

## What Setup changes

After explicit consent, Setup:

- installs to `%LOCALAPPDATA%\Programs\yt-seb`;
- downloads private copies of yt-dlp and Deno from their official HTTPS release
  locations, plus a Windows FFmpeg build from the gyan.dev build provider;
- adds the installation folder to the current user's `PATH`; and
- registers a per-user uninstaller.

Setup does not add a service, scheduled task, startup entry, driver, browser
extension, telemetry component, or administrator-level PATH entry. See
[`SECURITY.md`](SECURITY.md) for the complete security behavior.

## Uninstall

Use **Settings → Apps → Installed apps → yt-seb**. Uninstalling removes yt-seb
and its private dependency copies but does not delete music.

## Branches

- `main` contains the stable search-and-download command.
- `development` contains work in progress, including the experimental `-si`
  song-analysis and metadata feature.

## Legal

Download only media you have permission to download and use. You are responsible
for complying with YouTube's terms, copyright law, and applicable local law.

The yt-seb source is available under the [MIT License](LICENSE). Third-party
tools downloaded by Setup remain governed by their respective licenses.
