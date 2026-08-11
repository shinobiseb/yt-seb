# Security

## Installer behavior

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

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository
instead of publishing an exploitable issue.

Do not include passwords, authentication tokens, cookies, downloaded media, or
other sensitive personal data in a report.

