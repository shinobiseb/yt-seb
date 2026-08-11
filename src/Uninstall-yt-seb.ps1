$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$InstallFolder = Join-Path $env:LOCALAPPDATA 'Programs\yt-seb'
$ExpectedFolder = [IO.Path]::GetFullPath($InstallFolder).TrimEnd('\')
$ActualFolder = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')

if (-not $ActualFolder.Equals($ExpectedFolder, [StringComparison]::OrdinalIgnoreCase)) {
    [Windows.Forms.MessageBox]::Show(
        'Safety check failed: the uninstaller is not running from the expected yt-seb folder.',
        'yt-seb Uninstaller', 'OK', 'Error') | Out-Null
    exit 1
}

$Answer = [Windows.Forms.MessageBox]::Show(
    "Remove yt-seb and its private copies of yt-dlp, FFmpeg, and Deno?`n`nThis does not remove downloaded music.",
    'Uninstall yt-seb', 'YesNo', 'Question')

if ($Answer -ne [Windows.Forms.DialogResult]::Yes) { exit 0 }

$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $UserPath) { $UserPath = '' }
$NewPath = (($UserPath -split ';') | Where-Object {
    $_ -and -not $_.TrimEnd('\').Equals($ExpectedFolder, [StringComparison]::OrdinalIgnoreCase)
}) -join ';'
[Environment]::SetEnvironmentVariable('Path', $NewPath, 'User')

$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\yt-seb'
Remove-Item -LiteralPath $UninstallKey -Recurse -Force -ErrorAction SilentlyContinue

$Cleanup = Join-Path $env:TEMP ("yt-seb-cleanup-{0}.cmd" -f [guid]::NewGuid())
$CleanupLines = @(
    '@echo off',
    'ping 127.0.0.1 -n 3 >nul',
    ('rmdir /s /q "{0}"' -f $ExpectedFolder),
    'del /q "%~f0"'
)
Set-Content -LiteralPath $Cleanup -Value $CleanupLines -Encoding ASCII
Start-Process -FilePath $env:ComSpec -ArgumentList '/d', '/c', "`"$Cleanup`"" -WindowStyle Hidden

[Windows.Forms.MessageBox]::Show(
    'yt-seb has been removed from your user PATH. Its installation folder will now be deleted. Downloaded music was not changed.',
    'yt-seb Uninstaller', 'OK', 'Information') | Out-Null

