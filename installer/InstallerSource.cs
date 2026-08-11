using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class Program
{
    private const string YtDlpUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe";
    private const string FfmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip";
    private const string DenoUrl = "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip";

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam,
        string lParam, uint flags, uint timeout, out UIntPtr result);

    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        using (ConsentForm consent = new ConsentForm())
        {
            if (consent.ShowDialog() != DialogResult.OK)
                return;
        }

        Application.Run(new ProgressForm());
    }

    private sealed class ConsentForm : Form
    {
        public ConsentForm()
        {
            Text = "Install yt-seb";
            ClientSize = new Size(630, 440);
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowIcon = false;

            Label heading = new Label {
                Text = "Your confirmation is required",
                Font = new Font(SystemFonts.MessageBoxFont.FontFamily, 15, FontStyle.Bold),
                AutoSize = true, Location = new Point(24, 22)
            };

            RichTextBox disclosure = new RichTextBox {
                ReadOnly = true, BorderStyle = BorderStyle.FixedSingle,
                BackColor = SystemColors.Window, Location = new Point(24, 65),
                Size = new Size(582, 300), Font = new Font("Segoe UI", 10),
                Text =
                    "By selecting I Agree, installation will begin for the YouTube song downloader yt-seb on this device.\n\n" +
                    "Setup will install yt-seb for your Windows user under:\n" +
                    "%LOCALAPPDATA%\\Programs\\yt-seb\n\n" +
                    "It will download yt-dlp, FFmpeg, and Deno over HTTPS from their official publisher URLs, " +
                    "add the yt-seb folder to your user PATH so the command works in new terminals, and register an uninstaller.\n\n" +
                    "It will NOT request administrator privileges, install a background service, create a scheduled task, " +
                    "add a startup program, collect telemetry, or delete downloaded music during uninstall.\n\n" +
                    "yt-seb searches YouTube and downloads MP3 audio. Use it only for media you have permission to download. " +
                    "Select Cancel to exit without making any changes."
            };

            Button agree = new Button {
                Text = "I Agree", DialogResult = DialogResult.OK,
                Location = new Point(418, 386), Size = new Size(90, 32)
            };
            Button cancel = new Button {
                Text = "Cancel", DialogResult = DialogResult.Cancel,
                Location = new Point(516, 386), Size = new Size(90, 32)
            };

            Controls.Add(heading);
            Controls.Add(disclosure);
            Controls.Add(agree);
            Controls.Add(cancel);
            AcceptButton = agree;
            CancelButton = cancel;
        }
    }

    private sealed class ProgressForm : Form
    {
        private readonly TextBox log;
        private readonly ProgressBar bar;
        private readonly Button close;
        private readonly BackgroundWorker worker;

        public ProgressForm()
        {
            Text = "Installing yt-seb";
            ClientSize = new Size(650, 390);
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            ShowIcon = false;
            ControlBox = false;

            Label heading = new Label {
                Text = "Installing yt-seb for the current Windows user",
                Font = new Font(SystemFonts.MessageBoxFont.FontFamily, 12, FontStyle.Bold),
                AutoSize = true, Location = new Point(20, 18)
            };
            log = new TextBox {
                Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
                Location = new Point(20, 55), Size = new Size(610, 255),
                Font = new Font("Consolas", 9), BackColor = SystemColors.Window
            };
            bar = new ProgressBar {
                Location = new Point(20, 326), Size = new Size(500, 22),
                Style = ProgressBarStyle.Marquee, MarqueeAnimationSpeed = 25
            };
            close = new Button {
                Text = "Close", Location = new Point(540, 322), Size = new Size(90, 30),
                Enabled = false
            };
            close.Click += delegate { Close(); };

            Controls.Add(heading);
            Controls.Add(log);
            Controls.Add(bar);
            Controls.Add(close);

            worker = new BackgroundWorker();
            worker.DoWork += delegate(object sender, DoWorkEventArgs e) {
                Install(AppendLog);
            };
            worker.RunWorkerCompleted += delegate(object sender, RunWorkerCompletedEventArgs e) {
                bar.Style = ProgressBarStyle.Blocks;
                bar.Value = e.Error == null ? 100 : 0;
                close.Enabled = true;
                ControlBox = true;
                if (e.Error == null) {
                    AppendLog("Installation complete. Open a new terminal and run: yt-seb <song title>");
                    MessageBox.Show(this,
                        "yt-seb was installed successfully.\n\nOpen a new Command Prompt or PowerShell window, then run:\nyt-seb <song title>",
                        "yt-seb installed", MessageBoxButtons.OK, MessageBoxIcon.Information);
                } else {
                    AppendLog("INSTALLATION FAILED: " + e.Error.Message);
                    MessageBox.Show(this,
                        "yt-seb was not fully installed.\n\n" + e.Error.Message +
                        "\n\nReview the installation log. No PATH change is made until all downloads succeed.",
                        "yt-seb installation failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            };
            Shown += delegate { worker.RunWorkerAsync(); };
        }

        private void AppendLog(string message)
        {
            if (InvokeRequired) {
                BeginInvoke(new Action<string>(AppendLog), message);
                return;
            }
            log.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] " + message + Environment.NewLine);
        }
    }

    private static void Install(Action<string> report)
    {
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
        string target = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "yt-seb");
        string stage = Path.Combine(Path.GetTempPath(), "yt-seb-setup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(stage);

        try {
            report("Preparing a private staging folder.");
            ExtractResource("payload.yt-seb.cmd", Path.Combine(stage, "yt-seb.cmd"));
            ExtractResource("payload.yt-seb.ps1", Path.Combine(stage, "yt-seb.ps1"));
            ExtractResource("payload.Uninstall-yt-seb.ps1", Path.Combine(stage, "Uninstall-yt-seb.ps1"));

            string ytDlp = Path.Combine(stage, "yt-dlp.exe");
            report("Downloading yt-dlp from its official GitHub release...");
            Download(YtDlpUrl, ytDlp);
            RequireFile(ytDlp, 1024 * 1024, "yt-dlp.exe");

            string denoZip = Path.Combine(stage, "deno.zip");
            string denoExtract = Path.Combine(stage, "deno-extracted");
            report("Downloading Deno from its official GitHub release...");
            Download(DenoUrl, denoZip);
            ZipFile.ExtractToDirectory(denoZip, denoExtract);
            string denoFound = FindFile(denoExtract, "deno.exe");
            if (denoFound == null) throw new InvalidDataException("The Deno archive did not contain deno.exe.");
            File.Copy(denoFound, Path.Combine(stage, "deno.exe"), true);

            string ffmpegZip = Path.Combine(stage, "ffmpeg.zip");
            string ffmpegExtract = Path.Combine(stage, "ffmpeg-extracted");
            report("Downloading FFmpeg essentials from gyan.dev...");
            Download(FfmpegUrl, ffmpegZip);
            ZipFile.ExtractToDirectory(ffmpegZip, ffmpegExtract);
            string ffmpegFound = FindFile(ffmpegExtract, "ffmpeg.exe");
            if (ffmpegFound == null) throw new InvalidDataException("The FFmpeg archive did not contain ffmpeg.exe.");
            File.Copy(ffmpegFound, Path.Combine(stage, "ffmpeg.exe"), true);

            report("Calculating dependency SHA-256 hashes.");
            StringBuilder hashes = new StringBuilder();
            foreach (string name in new[] { "yt-dlp.exe", "ffmpeg.exe", "deno.exe" })
                hashes.AppendLine(Sha256(Path.Combine(stage, name)) + "  " + name);
            File.WriteAllText(Path.Combine(stage, "DEPENDENCY-HASHES.txt"), hashes.ToString(), Encoding.UTF8);

            string manifest =
                "yt-seb per-user installation\r\n" +
                "Installed: " + DateTime.UtcNow.ToString("u") + " UTC\r\n\r\n" +
                "Downloaded over HTTPS from:\r\n" + YtDlpUrl + "\r\n" + FfmpegUrl + "\r\n" + DenoUrl + "\r\n";
            File.WriteAllText(Path.Combine(stage, "INSTALLATION.txt"), manifest, Encoding.UTF8);

            report("All downloads succeeded. Installing files to " + target);
            Directory.CreateDirectory(target);
            foreach (string name in new[] {
                "yt-seb.cmd", "yt-seb.ps1", "Uninstall-yt-seb.ps1",
                "yt-dlp.exe", "ffmpeg.exe", "deno.exe",
                "DEPENDENCY-HASHES.txt", "INSTALLATION.txt" })
                File.Copy(Path.Combine(stage, name), Path.Combine(target, name), true);

            AddToUserPath(target);
            RegisterUninstaller(target);
            BroadcastEnvironmentChange();
            report("Added the yt-seb folder to the current user's PATH.");
        }
        finally {
            try { if (Directory.Exists(stage)) Directory.Delete(stage, true); } catch { }
        }
    }

    private static void Download(string url, string destination)
    {
        using (WebClient client = new WebClient()) {
            client.Headers.Add(HttpRequestHeader.UserAgent, "yt-seb-transparent-installer/1.0");
            client.DownloadFile(url, destination);
        }
    }

    private static void ExtractResource(string name, string destination)
    {
        using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) {
            if (input == null) throw new InvalidOperationException("Missing installer resource: " + name);
            using (FileStream output = File.Create(destination)) input.CopyTo(output);
        }
    }

    private static void RequireFile(string path, long minimumLength, string label)
    {
        if (!File.Exists(path) || new FileInfo(path).Length < minimumLength)
            throw new InvalidDataException("The downloaded " + label + " was missing or unexpectedly small.");
    }

    private static string FindFile(string root, string name)
    {
        return Directory.EnumerateFiles(root, name, SearchOption.AllDirectories).FirstOrDefault();
    }

    private static string Sha256(string path)
    {
        using (SHA256 sha = SHA256.Create())
        using (FileStream file = File.OpenRead(path))
            return BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "").ToLowerInvariant();
    }

    private static void AddToUserPath(string target)
    {
        string path = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? "";
        string[] parts = path.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries);
        bool exists = parts.Any(p => p.TrimEnd('\\').Equals(target.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase));
        if (!exists) {
            string updated = string.IsNullOrWhiteSpace(path) ? target : path.TrimEnd(';') + ";" + target;
            Environment.SetEnvironmentVariable("Path", updated, EnvironmentVariableTarget.User);
        }
    }

    private static void RegisterUninstaller(string target)
    {
        const string keyPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\yt-seb";
        using (RegistryKey key = Registry.CurrentUser.CreateSubKey(keyPath)) {
            key.SetValue("DisplayName", "yt-seb");
            key.SetValue("DisplayVersion", "1.0");
            key.SetValue("Publisher", "yt-seb local package");
            key.SetValue("InstallLocation", target);
            key.SetValue("NoModify", 1, RegistryValueKind.DWord);
            key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            string script = Path.Combine(target, "Uninstall-yt-seb.ps1");
            key.SetValue("UninstallString", "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"");
        }
    }

    private static void BroadcastEnvironmentChange()
    {
        UIntPtr result;
        SendMessageTimeout(new IntPtr(0xffff), 0x001A, UIntPtr.Zero, "Environment", 0x0002, 5000, out result);
    }
}

