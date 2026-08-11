# yt-seb for macOS

The macOS build provides the same relevance-ranked YouTube search, MP3
download, and experimental `-si` metadata mode as the Windows development
build. It supports Apple silicon and Intel Macs through Homebrew.

## Install

The macOS build is currently part of the `development` branch. In Terminal,
download the installer to a temporary file, inspect it if desired, and run it:

```bash
installer="$(mktemp)"
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/shinobiseb/yt-seb/development/mac/install-macos.sh -o "$installer" && bash "$installer"
status=$?; rm -f "$installer"; (exit "$status")
```

The installer displays a confirmation dialog describing every change. Nothing
is installed until you click **I Agree**. Installation is per-user and does not
use `sudo`. If dependencies are missing, it asks the existing Homebrew command
to install `yt-dlp`, `ffmpeg`, and `deno`. It does not install Homebrew itself.
This development installer and its payload are fetched from a mutable branch
over HTTPS; they are not a signed or notarized macOS app/package and the
bootstrap does not pin a release checksum. You can inspect the script before
running it. A tagged release should pin payload checksums before being promoted
as stable.

For a local clone, run `bash mac/install-macos.sh` from the repository instead.

## Use

Open a new Terminal window after installation:

```bash
yt-seb september earth wind and fire
yt-seb -si september earth wind and fire
```

Audio is saved to `~/Music`. The selected YouTube URL is copied with `pbcopy`.
`-si` estimates tempo and key locally, writes ID3 metadata, and uses this name:

```text
Song Title │ Artist │ 120 BPM │ Found Key │ [YT-Seb].mp3
```

## What the installer changes

- Creates `~/.local/bin/yt-seb` and `~/.local/bin/yt-seb-uninstall`.
- Stores helper files under `~/.local/share/yt-seb`.
- Adds a clearly marked `~/.local/bin` PATH block to `~/.zprofile` and, when
  already present, `~/.bash_profile`.
- Uses Homebrew to install only missing runtime dependencies.

It does not create a service, startup item, scheduled job, browser extension,
telemetry component, or system-wide PATH entry.

## Uninstall

```bash
yt-seb-uninstall
```

The uninstaller removes only the files and marked PATH blocks above. Downloaded
music and Homebrew packages are retained.

## Requirements and limitations

- macOS with Terminal and `curl`.
- `yt-dlp`, FFmpeg, and either Deno or Node.js. If these are not already
  available, the installer obtains the missing formulas through Homebrew.
- Tempo and key are estimates. No audio is uploaded for analysis.
- Download only media you have permission to download and use.
