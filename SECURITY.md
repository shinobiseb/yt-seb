# Security

## Windows installer behavior

The installer requires an interactive **I Agree** click before changing the
device. It installs for the current Windows user under
`%LOCALAPPDATA%\Programs\yt-seb`, downloads yt-dlp, FFmpeg, and Deno from the
official HTTPS URLs declared in `installer/InstallerSource.cs`, modifies only
the current user's PATH, and registers a reversible uninstaller.

It does not install a service, scheduled task, startup entry, driver, browser
extension, or telemetry component. It does not request administrator rights or
YouTube credentials. There is no silent-install switch.

The dependencies use publisher-controlled `latest` URLs. TLS protects downloads
in transit, but the installer cannot pin future publisher hashes in advance. It
records the downloaded executable hashes locally for auditing.

## macOS installer behavior

The development branch also includes a Bash installer under `mac/`. It first
shows a macOS confirmation dialog (or requires the exact terminal response
`I AGREE`) and stops on Cancel before staging files. It installs only for the
current user under `~/.local/bin` and `~/.local/share/yt-seb`, and adds a marked,
reversible PATH block to `~/.zprofile` and an existing `~/.bash_profile`.

The installer accepts existing yt-dlp, FFmpeg, and Deno or Node.js commands. If
dependencies are missing, it can ask an existing Homebrew installation to
install the required formulas. It never installs Homebrew, uses `sudo`, or adds
a service or startup item. The uninstaller leaves downloaded music and
Homebrew-managed packages in place.

The development bootstrap and payload use HTTPS from a mutable branch; they are
not a signed or notarized macOS package and are not pinned to release checksums.
Inspect the bootstrap before use. A stable macOS release should use an immutable
tag or commit and verify pinned payload hashes.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository
instead of publishing an exploitable issue.

Do not include passwords, authentication tokens, cookies, downloaded media, or
other sensitive personal data in a report.
