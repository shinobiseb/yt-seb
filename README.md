# yt-seb

`yt-seb` is a Windows command-line YouTube song downloader. Enter a song title
and it searches YouTube's top five relevance-ranked results, selects the first
usable result, copies its URL to the clipboard, and saves MP3 audio in your
Music folder.

## Install on Windows

Open PowerShell and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Join-Path $env:TEMP 'yt-seb-install.ps1'; Invoke-WebRequest 'https://raw.githubusercontent.com/shinobiseb/yt-seb/main/install.ps1' -OutFile $p; & $p"
```

This command downloads the repository's [`install.ps1`](install.ps1) to a
temporary file. That script downloads `dist/yt-seb Setup.exe`, verifies its
pinned SHA-256 checksum, and opens it. Setup does not install anything until you
read the disclosure and click **I Agree**. It installs only for the current
Windows user and does not request administrator privileges.

You may instead download the repository and run `dist/yt-seb Setup.exe`
manually.

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

## What Setup changes

After explicit consent, Setup:

- installs to `%LOCALAPPDATA%\Programs\yt-seb`;
- downloads private copies of yt-dlp, FFmpeg, and Deno over HTTPS from their
  official release locations;
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

