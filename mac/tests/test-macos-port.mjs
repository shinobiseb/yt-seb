import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const macDir = path.resolve(here, "..");
const bash = process.env.BASH_EXE || "C:\\Program Files\\Git\\bin\\bash.exe";

let passed = 0;
function test(name, fn) {
  try {
    fn();
    passed += 1;
    process.stdout.write(`ok ${passed} - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n${error.stack || error}\n`);
    process.exitCode = 1;
  }
}

function text(name) {
  return readFileSync(path.join(macDir, name), "utf8");
}

function bashPath(windowsPath) {
  return execFileSync(bash, ["-lc", `cygpath -u '${windowsPath.replaceAll("'", "'\\''")}'`], {
    encoding: "utf8",
  }).trim();
}

function writeExecutable(file, contents) {
  writeFileSync(file, contents.replace(/^\n/, ""), "utf8");
  chmodSync(file, 0o755);
}

function runBash(args, options = {}) {
  const result = spawnSync(bash, args, {
    encoding: "utf8",
    ...options,
  });
  if (result.error) throw result.error;
  return result;
}

for (const file of ["yt-seb", "install-macos.sh", "uninstall-macos.sh"]) {
  test(`${file} has valid Bash syntax`, () => {
    execFileSync(bash, ["-n", path.join(macDir, file)], { stdio: "pipe" });
  });
}

test("production shell scripts avoid eval, sudo, and Bash 4-only constructs", () => {
  const source = [text("yt-seb"), text("install-macos.sh"), text("uninstall-macos.sh")]
    .join("\n")
    .split("\n")
    .filter((line) => !/^\s*#/.test(line))
    .join("\n");
  // Disallow the shell builtins/commands. A fixed `node --eval` or `deno eval`
  // compatibility probe does not interpret user-controlled text in Bash.
  assert.doesNotMatch(source, /^\s*eval(?:\s|$)/m);
  assert.doesNotMatch(source, /^\s*sudo(?:\s|$)/m);
  assert.doesNotMatch(source, /declare\s+-A|\bmapfile\b|\breadarray\b|\bcoproc\b|\$\{[^}]+,,[^}]*\}/);
});

test("installer refuses non-macOS hosts", () => {
  const source = text("install-macos.sh");
  assert.match(source, /uname\s+-s/);
  assert.match(source, /Darwin/);
});

test("installer can find Homebrew on Apple silicon and Intel", () => {
  const source = text("install-macos.sh");
  assert.match(source, /\/opt\/homebrew\/bin\/brew/);
  assert.match(source, /\/usr\/local\/bin\/brew/);
});

test("consent disclosure precedes downloads, dependency changes, and installation", () => {
  const source = text("install-macos.sh");
  const consent = source.lastIndexOf("\nconfirm_installation\n");
  assert.ok(consent >= 0, "installer must call confirm_installation");
  assert.ok(consent < source.indexOf("Preparing yt-seb files", consent));
  assert.ok(consent < source.lastIndexOf("\nensure_dependencies\n"));
  assert.ok(consent < source.lastIndexOf("\nmkdir -p \"$APP_DIR\""));
  assert.match(source, /buttons \{\"Cancel\", \"I Agree\"\}/);
  assert.match(source, /current user/);
  assert.match(source, /\.local\/bin/);
  assert.match(source, /\.local\/share\/yt-seb/);
  assert.match(source, /Homebrew/);
  assert.match(source, /startup item/);
});

test("PATH block is explicit, idempotent, and removed by matching markers", () => {
  const installer = text("install-macos.sh");
  const uninstaller = text("uninstall-macos.sh");
  for (const marker of ["# >>> yt-seb >>>", "# <<< yt-seb <<<"]) {
    assert.ok(installer.includes(marker));
    assert.ok(uninstaller.includes(marker));
  }
  assert.ok(installer.includes('export PATH="$HOME/.local/bin:$PATH"'));
  assert.match(installer, /profile_state\(\)/);
  assert.match(installer, /\[ "\$state" = valid \] && return 0/);
});

test("uninstaller scope is limited and downloaded Music is never targeted", () => {
  const source = text("uninstall-macos.sh");
  assert.ok(source.includes('rm -f -- "$BIN_DIR/yt-seb"'));
  assert.ok(source.includes('rm -f -- "$BIN_DIR/yt-seb-uninstall"'));
  assert.ok(source.includes('[ -f "$APP_DIR/.yt-seb-macos-install" ]'));
  assert.ok(source.includes("leaving unrecognized command unchanged"));
  assert.ok(source.includes('rm -rf -- "$APP_DIR"'));
  assert.doesNotMatch(source, /rm\s+-[^\n]*\$HOME(?:[\s"']|$)/);
  assert.doesNotMatch(source, /rm\s+-[^\n]*(?:\/Music|DOWNLOAD_DIR)/);
});

test("regular CLI preserves a metacharacter-heavy query as one yt-dlp argument", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "yt-seb-cli-test-"));
  try {
    const fakeBin = path.join(root, "bin");
    const app = path.join(root, "app");
    const music = path.join(root, "Music");
    mkdirSync(fakeBin);
    mkdirSync(app);
    cpSync(path.join(macDir, "resolve-song-metadata.mjs"), path.join(app, "resolve-song-metadata.mjs"));
    cpSync(path.join(macDir, "runtime-helper.mjs"), path.join(app, "runtime-helper.mjs"));
    const log = path.join(root, "yt-dlp.log");
    const clip = path.join(root, "clipboard.txt");
    writeExecutable(path.join(fakeBin, "yt-dlp"), `
#!/usr/bin/env bash
for value in "$@"; do printf 'ARG=%s\\n' "$value" >> "$TEST_LOG"; done
for value in "$@"; do
  if [ "$value" = '--print' ]; then printf 'abc123_XY09\\tA Result Title\\nzzz999_ABCD\\tAnother Result\\n'; exit 0; fi
done
exit 0
`);
    writeExecutable(path.join(fakeBin, "ffmpeg"), "#!/usr/bin/env bash\nexit 0\n");
    writeExecutable(path.join(fakeBin, "pbcopy"), '#!/usr/bin/env bash\ncat > "$TEST_CLIP"\n');
    const injectionTarget = path.join(root, "MUST_NOT_EXIST");
    const dangerous = `weird song ; $(touch ${bashPath(injectionTarget)}) "quoted"`;
    const fakeBinBash = bashPath(fakeBin);
    const env = {
      ...process.env,
      YT_SEB_APP_DIR: bashPath(app),
      YT_SEB_MUSIC_DIR: bashPath(music),
      TEST_LOG: bashPath(log),
      TEST_CLIP: bashPath(clip),
    };
    const result = runBash(["-c", 'export PATH="$1:$PATH"; shift; exec "$@"', "test", fakeBinBash,
      bashPath(path.join(macDir, "yt-seb")), dangerous], { env });
    assert.equal(result.status, 0, result.stderr);
    assert.ok(readFileSync(log, "utf8").split(/\r?\n/).includes(`ARG=ytsearch5:${dangerous}`));
    assert.equal(readFileSync(clip, "utf8"), "https://www.youtube.com/watch?v=abc123_XY09");
    assert.match(result.stdout, /Selected: A Result Title/);
    assert.match(result.stdout, /File downloaded!/);
    assert.equal(existsSync(injectionTarget), false, "query text was executed by a shell");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("-si CLI writes a tagged filename using resolved metadata and local analysis", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "yt-seb-si-test-"));
  try {
    const fakeBin = path.join(root, "bin");
    const app = path.join(root, "app");
    const music = path.join(root, "Music");
    mkdirSync(fakeBin);
    mkdirSync(app);
    cpSync(path.join(macDir, "resolve-song-metadata.mjs"), path.join(app, "resolve-song-metadata.mjs"));
    cpSync(path.join(macDir, "runtime-helper.mjs"), path.join(app, "runtime-helper.mjs"));
    writeFileSync(path.join(app, "analyze-audio.mjs"), 'process.stdout.write(JSON.stringify({tempo:123,key:"C major"}));\n');
    writeExecutable(path.join(fakeBin, "yt-dlp"), `
#!/usr/bin/env bash
for value in "$@"; do
  if [ "$value" = '--print' ]; then printf 'abc123_XY09\\tReal Song (Official Audio)\\n'; exit 0; fi
  if [ "$value" = '--dump-single-json' ]; then
    printf '%s\\n' '{"title":"Real Song (Official Audio)","track":"Real Song","uploader":"Great Artist - Topic","channel":"Great Artist - Topic"}'
    exit 0
  fi
done
previous=''
for value in "$@"; do
  if [ "$previous" = '-o' ]; then output=$value; output=\${output//'%(ext)s'/mp3}; mkdir -p "$(dirname "$output")"; : > "$output"; exit 0; fi
  previous=$value
done
exit 0
`);
    writeExecutable(path.join(fakeBin, "ffmpeg"), `
#!/usr/bin/env bash
for last in "$@"; do :; done
mkdir -p "$(dirname "$last")"
: > "$last"
`);
    const env = {
      ...process.env,
      YT_SEB_APP_DIR: bashPath(app),
      YT_SEB_MUSIC_DIR: bashPath(music),
    };
    const result = runBash(["-c", 'export PATH="$1:$PATH"; shift; exec "$@"', "test", bashPath(fakeBin),
      bashPath(path.join(macDir, "yt-seb")), "-si", "Real Song"], { env });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Title:\s+Real Song/);
    assert.match(result.stdout, /Artist:\s+Great Artist/);
    assert.match(result.stdout, /Tempo: 123 BPM/);
    assert.match(result.stdout, /Key:\s+C major/);
    const expected = path.join(music, "Real Song │ Great Artist │ 123 BPM │ C major │ [YT-Seb].mp3");
    assert.equal(existsSync(expected), true, `expected output file ${expected}`);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("cancelled GUI consent makes no persistent installation changes", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "yt-seb-consent-test-"));
  try {
    const fakeBin = path.join(root, "bin");
    const home = path.join(root, "home");
    mkdirSync(fakeBin);
    mkdirSync(home);
    writeExecutable(path.join(fakeBin, "uname"), "#!/usr/bin/env bash\nprintf 'Darwin\\n'\n");
    writeExecutable(path.join(fakeBin, "osascript"), "#!/usr/bin/env bash\nexit 1\n");
    const env = { ...process.env, HOME: bashPath(home) };
    const result = runBash(["-c", 'export PATH="$1:$PATH"; shift; exec "$@"', "test", bashPath(fakeBin),
      bashPath(path.join(macDir, "install-macos.sh"))], { env });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Installation cancelled/);
    assert.equal(existsSync(path.join(home, ".local")), false);
    assert.equal(existsSync(path.join(home, ".zprofile")), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("malformed PATH markers fail preflight before installation mutations", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "yt-seb-marker-test-"));
  try {
    const fakeBin = path.join(root, "bin");
    const home = path.join(root, "home");
    const brewLog = path.join(root, "brew.log");
    mkdirSync(fakeBin);
    mkdirSync(home);
    writeFileSync(path.join(home, ".zprofile"), "keep me\n# >>> yt-seb >>>\n");
    writeExecutable(path.join(fakeBin, "uname"), "#!/usr/bin/env bash\nprintf 'Darwin\\n'\n");
    writeExecutable(path.join(fakeBin, "osascript"), "#!/usr/bin/env bash\nprintf 'I Agree\\n'\n");
    writeExecutable(path.join(fakeBin, "brew"), '#!/usr/bin/env bash\nprintf called > "$TEST_BREW_LOG"\nexit 99\n');
    const env = { ...process.env, HOME: bashPath(home), TEST_BREW_LOG: bashPath(brewLog) };
    const result = runBash(["-c", 'export PATH="$1:$PATH"; shift; exec "$@"', "test", bashPath(fakeBin),
      bashPath(path.join(macDir, "install-macos.sh"))], { env });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /malformed yt-seb PATH markers/);
    assert.equal(readFileSync(path.join(home, ".zprofile"), "utf8"), "keep me\n# >>> yt-seb >>>\n");
    assert.equal(existsSync(path.join(home, ".local")), false);
    assert.equal(existsSync(brewLog), false, "dependency installer ran before profile validation");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("symlinked profile fails preflight before installation mutations", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "yt-seb-profile-link-test-"));
  try {
    const fakeBin = path.join(root, "bin");
    const home = path.join(root, "home");
    const target = path.join(root, "profile-target");
    const profile = path.join(home, ".zprofile");
    mkdirSync(fakeBin);
    mkdirSync(home);
    writeFileSync(target, "do not change\n");
    writeExecutable(path.join(fakeBin, "uname"), "#!/usr/bin/env bash\nprintf 'Darwin\\n'\n");
    writeExecutable(path.join(fakeBin, "osascript"), "#!/usr/bin/env bash\nprintf 'I Agree\\n'\n");
    const linkResult = runBash(["-c", 'ln -s "$1" "$2"; [ -L "$2" ]', "test", bashPath(target), bashPath(profile)]);
    if (linkResult.status !== 0) {
      // Git Bash commonly lacks Windows symlink privileges. Keep a structural
      // regression so the native-mac behavior remains ordered before staging.
      const source = text("install-macos.sh");
      assert.match(source, /\[ ! -L "\$profile" \].*refusing symlinked shell profile/);
      assert.ok(source.indexOf('profile_state "$HOME/.zprofile"') < source.indexOf('STAGE_DIR="$(mktemp -d'));
      return;
    }
    const env = { ...process.env, HOME: bashPath(home) };
    const result = runBash(["-c", 'export PATH="$1:$PATH"; shift; exec "$@"', "test", bashPath(fakeBin),
      bashPath(path.join(macDir, "install-macos.sh"))], { env });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /refusing symlinked shell profile/);
    assert.equal(readFileSync(target, "utf8"), "do not change\n");
    assert.equal(existsSync(path.join(home, ".local")), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("an old Node runtime is rejected instead of satisfying dependencies", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "yt-seb-old-node-test-"));
  try {
    const fakeBin = path.join(root, "bin");
    const home = path.join(root, "home");
    mkdirSync(fakeBin);
    mkdirSync(home);
    writeExecutable(path.join(fakeBin, "uname"), "#!/usr/bin/env bash\nprintf 'Darwin\\n'\n");
    writeExecutable(path.join(fakeBin, "osascript"), "#!/usr/bin/env bash\nprintf 'I Agree\\n'\n");
    writeExecutable(path.join(fakeBin, "yt-dlp"), "#!/usr/bin/env bash\nexit 0\n");
    writeExecutable(path.join(fakeBin, "ffmpeg"), "#!/usr/bin/env bash\nexit 0\n");
    writeExecutable(path.join(fakeBin, "node"), "#!/usr/bin/env bash\n[ \"${1:-}\" = '--version' ] && printf 'v16.20.2\\n'\nexit 0\n");
    const env = { ...process.env, HOME: bashPath(home) };
    const result = runBash(["-c", 'export PATH="$1:/usr/bin:/bin"; shift; exec "$@"', "test", bashPath(fakeBin),
      bashPath(path.join(macDir, "install-macos.sh"))], { env });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /missing dependencies: deno/);
    assert.equal(existsSync(path.join(home, ".local")), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("emoji and CJK song basename reserves collision suffix within 255 UTF-8 bytes", () => {
  const helper = path.join(macDir, "runtime-helper.mjs");
  const title = "🎵東京夜曲".repeat(40);
  const artist = "藝術家✨".repeat(40);
  const key = "嬰ハ長調🎹".repeat(20);
  const basename = execFileSync(process.execPath, [helper, "song-basename", title, artist, "128", key], {
    encoding: "utf8",
  });
  assert.ok(basename.includes("🎵"));
  assert.ok(basename.includes("藝術家"));
  assert.ok(basename.endsWith("│ [YT-Seb]"));
  assert.ok(Buffer.byteLength(`${basename} (9999).mp3`, "utf8") <= 255);
});

test("accepted local install is per-user and writes one marked PATH block", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "yt-seb-install-test-"));
  try {
    const fakeBin = path.join(root, "bin");
    const home = path.join(root, "home");
    mkdirSync(fakeBin);
    mkdirSync(home);
    writeExecutable(path.join(fakeBin, "uname"), "#!/usr/bin/env bash\nprintf 'Darwin\\n'\n");
    writeExecutable(path.join(fakeBin, "osascript"), "#!/usr/bin/env bash\nprintf 'I Agree\\n'\n");
    writeExecutable(path.join(fakeBin, "yt-dlp"), "#!/usr/bin/env bash\nexit 0\n");
    writeExecutable(path.join(fakeBin, "ffmpeg"), "#!/usr/bin/env bash\nexit 0\n");
    const env = { ...process.env, HOME: bashPath(home) };
    const command = ["-c", 'export PATH="$1:$PATH"; shift; exec "$@"', "test", bashPath(fakeBin),
      bashPath(path.join(macDir, "install-macos.sh"))];
    const result = runBash(command, { env });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /installed for the current user/);
    const app = path.join(home, ".local", "share", "yt-seb");
    const bin = path.join(home, ".local", "bin");
    for (const file of ["resolve-song-metadata.mjs", "runtime-helper.mjs", "analyze-audio.mjs",
      "uninstall-macos.sh", ".yt-seb-macos-install"]) {
      assert.equal(existsSync(path.join(app, file)), true, `missing installed file ${file}`);
    }
    assert.equal(existsSync(path.join(bin, "yt-seb")), true);
    assert.equal(existsSync(path.join(bin, "yt-seb-uninstall")), true);
    const profile = readFileSync(path.join(home, ".zprofile"), "utf8");
    assert.equal((profile.match(/# >>> yt-seb >>>/g) || []).length, 1);
    assert.equal((profile.match(/# <<< yt-seb <<</g) || []).length, 1);
    assert.match(profile, /export PATH="\$HOME\/\.local\/bin:\$PATH"/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("uninstaller keeps music and unrelated files while removing its own scope", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "yt-seb-uninstall-test-"));
  try {
    const home = path.join(root, "home");
    const bin = path.join(home, ".local", "bin");
    const app = path.join(home, ".local", "share", "yt-seb");
    const music = path.join(home, "Music");
    mkdirSync(bin, { recursive: true });
    mkdirSync(app, { recursive: true });
    mkdirSync(music, { recursive: true });
    writeFileSync(path.join(bin, "yt-seb"), "#!/usr/bin/env bash\n# yt-seb macOS command\n");
    for (const file of ["yt-seb-uninstall", "unrelated-tool"]) writeFileSync(path.join(bin, file), file);
    writeFileSync(path.join(app, "helper"), "data");
    writeFileSync(path.join(app, ".yt-seb-macos-install"), "installed\n");
    writeFileSync(path.join(music, "song.mp3"), "music");
    const profile = path.join(home, ".zprofile");
    writeFileSync(profile, 'before\n# >>> yt-seb >>>\nexport PATH="$HOME/.local/bin:$PATH"\n# <<< yt-seb <<<\nafter\n');
    const fakeBin = path.join(root, "fake-bin");
    mkdirSync(fakeBin);
    writeExecutable(path.join(fakeBin, "uname"), "#!/usr/bin/env bash\nprintf 'Darwin\\n'\n");
    const result = runBash(["-c", 'export PATH="$1:$PATH"; printf \'y\\n\' | "$2"', "test", bashPath(fakeBin),
      bashPath(path.join(macDir, "uninstall-macos.sh"))], {
      env: { ...process.env, HOME: bashPath(home) },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(existsSync(path.join(bin, "yt-seb")), false);
    assert.equal(existsSync(path.join(bin, "yt-seb-uninstall")), true, "unrecognized files must be preserved");
    assert.equal(existsSync(path.join(bin, "unrelated-tool")), true);
    assert.equal(existsSync(app), false);
    assert.equal(existsSync(path.join(music, "song.mp3")), true);
    assert.equal(readFileSync(profile, "utf8"), "before\nafter\n");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

if (!process.exitCode) process.stdout.write(`1..${passed}\n`);
