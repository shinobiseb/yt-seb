#!/usr/bin/env bash

set -euo pipefail
umask 077

case "${HOME:-}" in /*) ;; *) printf '%s\n' 'Error: HOME must be an absolute path.' >&2; exit 1 ;; esac
[ "$(uname -s)" = 'Darwin' ] || { printf '%s\n' 'Error: this installer supports macOS only.' >&2; exit 1; }

REPOSITORY_RAW_URL="${YT_SEB_RAW_URL:-https://raw.githubusercontent.com/shinobiseb/yt-seb/development}"
APP_DIR="$HOME/.local/share/yt-seb"
BIN_DIR="$HOME/.local/bin"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
STAGE_DIR=''
LOCAL_REPO_ROOT=''
cleanup() { if [ -n "$STAGE_DIR" ]; then rm -rf -- "$STAGE_DIR"; fi; }

candidate_root="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
if [ -f "$candidate_root/LICENSE" ] && [ -f "$candidate_root/mac/yt-seb" ] && \
  [ -f "$candidate_root/mac/resolve-song-metadata.mjs" ] && \
  [ -f "$candidate_root/mac/runtime-helper.mjs" ] && \
  [ -f "$candidate_root/src/analyze-audio.mjs" ] && \
  [ -f "$candidate_root/mac/uninstall-macos.sh" ]; then
  LOCAL_REPO_ROOT=$candidate_root
fi

DISCLOSURE='By selecting I Agree, installation of the YouTube song downloader yt-seb will begin on this Mac for the current user. The installer may download program files over HTTPS, creates ~/.local/bin/yt-seb and ~/.local/share/yt-seb, and adds a marked ~/.local/bin PATH block to ~/.zprofile and to an existing ~/.bash_profile. If needed, it runs brew install for yt-dlp, ffmpeg, and deno; an interrupted install can leave those Homebrew packages installed. It does not use sudo, request administrator access, add a service or startup item, or include telemetry. Download only media you have permission to use.'

confirm_installation() {
  if command -v osascript >/dev/null 2>&1; then
    local answer
    if ! answer="$(osascript -e 'set disclosure to "'"${DISCLOSURE//\"/\\\"}"'"' -e 'button returned of (display dialog disclosure with title "Install yt-seb" buttons {"Cancel", "I Agree"} default button "I Agree" cancel button "Cancel" with icon caution)')"; then
      printf '%s\n' 'Installation cancelled.'
      exit 0
    fi
    [ "$answer" = 'I Agree' ] || exit 0
  else
    printf '\n%s\n\nType I AGREE to begin, or press Enter to cancel: ' "$DISCLOSURE"
    IFS= read -r answer
    [ "$answer" = 'I AGREE' ] || { printf '%s\n' 'Installation cancelled.'; exit 0; }
  fi
}

fetch_payload() {
  local relative_path=$1 destination=$2
  if [ -n "$LOCAL_REPO_ROOT" ]; then
    cp "$LOCAL_REPO_ROOT/$relative_path" "$destination"
  else
    command -v curl >/dev/null 2>&1 || { printf '%s\n' 'Error: curl is required.' >&2; exit 1; }
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
      "$REPOSITORY_RAW_URL/$relative_path" --output "$destination"
  fi
}

ensure_dependencies() {
  local brew_path='' brew_prefix=''
  local missing=()
  if command -v brew >/dev/null 2>&1; then brew_path="$(command -v brew)"
  elif [ -x /opt/homebrew/bin/brew ]; then brew_path=/opt/homebrew/bin/brew
  elif [ -x /usr/local/bin/brew ]; then brew_path=/usr/local/bin/brew
  fi
  if [ -n "$brew_path" ]; then
    brew_prefix="$($brew_path --prefix)"
    PATH="$brew_prefix/bin:$PATH"
    export PATH
  fi
  command -v yt-dlp >/dev/null 2>&1 || missing+=(yt-dlp)
  command -v ffmpeg >/dev/null 2>&1 || missing+=(ffmpeg)
  local deno_works=1 node_works=1 deno_path='' node_path=''
  deno_path="$(command -v deno 2>/dev/null || true)"
  node_path="$(command -v node 2>/dev/null || true)"
  if [ -n "$deno_path" ] && "$deno_path" --version >/dev/null 2>&1; then deno_works=0; fi
  if [ -n "$node_path" ]; then
    local node_version node_major
    node_version="$("$node_path" --version 2>/dev/null || true)"
    node_major=${node_version#v}
    node_major=${node_major%%.*}
    case "$node_major" in *[!0-9]*|'') ;; *) if [ "$node_major" -ge 18 ]; then node_works=0; fi ;; esac
  fi
  if [ "$deno_works" -ne 0 ] && [ "$node_works" -ne 0 ]; then
    missing+=(deno)
  fi
  [ "${#missing[@]}" -gt 0 ] || return 0
  if [ -z "$brew_path" ]; then
    printf 'Error: missing dependencies: %s\n' "${missing[*]}" >&2
    printf '%s\n' 'Install Homebrew from https://brew.sh and run this installer again.' >&2
    exit 1
  fi
  "$brew_path" install "${missing[@]}"
}

profile_state() {
  local profile=$1 begin_count end_count
  [ ! -L "$profile" ] || { printf '%s\n' "Error: refusing symlinked shell profile: $profile" >&2; return 1; }
  [ -f "$profile" ] || { printf '%s\n' absent; return 0; }
  begin_count="$(grep -Fxc '# >>> yt-seb >>>' "$profile" || true)"
  end_count="$(grep -Fxc '# <<< yt-seb <<<' "$profile" || true)"
  if [ "$begin_count" -eq 0 ] && [ "$end_count" -eq 0 ]; then printf '%s\n' absent; return 0; fi
  if [ "$begin_count" -ne 1 ] || [ "$end_count" -ne 1 ]; then
    printf '%s\n' "Error: malformed yt-seb PATH markers in $profile" >&2
    return 1
  fi
  if awk '
    $0 == "# >>> yt-seb >>>" { if (state) exit 2; state=1; next }
    state == 1 { if ($0 != "export PATH=\"$HOME/.local/bin:$PATH\"") exit 2; state=2; next }
    state == 2 { if ($0 != "# <<< yt-seb <<<") exit 2; state=0; complete=1; next }
    $0 == "# <<< yt-seb <<<" { exit 2 }
    END { if (state || !complete) exit 2 }
  ' "$profile"; then
    printf '%s\n' valid
  else
    printf '%s\n' "Error: malformed yt-seb PATH block in $profile" >&2
    return 1
  fi
}

add_path_block() {
  local profile=$1 state
  state="$(profile_state "$profile")"
  [ "$state" = valid ] && return 0
  touch "$profile"
  {
    printf '\n%s\n' '# >>> yt-seb >>>'
    printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"'
    printf '%s\n' '# <<< yt-seb <<<'
  } >> "$profile"
}

confirm_installation
# Validate every profile that may be changed before downloads, Homebrew, or app files.
profile_state "$HOME/.zprofile" >/dev/null
if [ -f "$HOME/.bash_profile" ] || [ -L "$HOME/.bash_profile" ]; then
  profile_state "$HOME/.bash_profile" >/dev/null
fi
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yt-seb-install.XXXXXX")"
trap cleanup EXIT HUP INT TERM
[ ! -L "$APP_DIR" ] || { printf '%s\n' "Error: refusing symlinked install path: $APP_DIR" >&2; exit 1; }
[ ! -L "$BIN_DIR/yt-seb" ] || { printf '%s\n' "Error: refusing symlinked command target: $BIN_DIR/yt-seb" >&2; exit 1; }
if [ -e "$APP_DIR" ] && [ ! -f "$APP_DIR/.yt-seb-macos-install" ]; then
  printf '%s\n' "Error: refusing to overwrite an unrecognized directory: $APP_DIR" >&2
  exit 1
fi
if [ -e "$BIN_DIR/yt-seb" ] && [ ! -f "$APP_DIR/.yt-seb-macos-install" ]; then
  printf '%s\n' "Error: refusing to overwrite an existing command: $BIN_DIR/yt-seb" >&2
  exit 1
fi
if [ -e "$BIN_DIR/yt-seb-uninstall" ] || [ -L "$BIN_DIR/yt-seb-uninstall" ]; then
  expected_uninstaller="$APP_DIR/uninstall-macos.sh"
  actual_uninstaller="$(readlink "$BIN_DIR/yt-seb-uninstall" 2>/dev/null || true)"
  [ "$actual_uninstaller" = "$expected_uninstaller" ] || {
    printf '%s\n' "Error: refusing to overwrite an existing command: $BIN_DIR/yt-seb-uninstall" >&2
    exit 1
  }
fi
printf '%s\n' 'Preparing yt-seb files...'
fetch_payload 'mac/yt-seb' "$STAGE_DIR/yt-seb"
fetch_payload 'mac/resolve-song-metadata.mjs' "$STAGE_DIR/resolve-song-metadata.mjs"
fetch_payload 'mac/runtime-helper.mjs' "$STAGE_DIR/runtime-helper.mjs"
fetch_payload 'src/analyze-audio.mjs' "$STAGE_DIR/analyze-audio.mjs"
fetch_payload 'mac/uninstall-macos.sh' "$STAGE_DIR/uninstall-macos.sh"

ensure_dependencies
mkdir -p "$APP_DIR" "$BIN_DIR"
install -m 755 "$STAGE_DIR/yt-seb" "$BIN_DIR/yt-seb"
install -m 644 "$STAGE_DIR/resolve-song-metadata.mjs" "$APP_DIR/resolve-song-metadata.mjs"
install -m 644 "$STAGE_DIR/runtime-helper.mjs" "$APP_DIR/runtime-helper.mjs"
install -m 644 "$STAGE_DIR/analyze-audio.mjs" "$APP_DIR/analyze-audio.mjs"
install -m 755 "$STAGE_DIR/uninstall-macos.sh" "$APP_DIR/uninstall-macos.sh"
printf '%s\n' 'yt-seb macOS per-user installation' > "$APP_DIR/.yt-seb-macos-install"
ln -sfn "$APP_DIR/uninstall-macos.sh" "$BIN_DIR/yt-seb-uninstall"

add_path_block "$HOME/.zprofile"
if [ -f "$HOME/.bash_profile" ]; then add_path_block "$HOME/.bash_profile"; fi

printf '\nyt-seb was installed for the current user.\n'
printf 'Open a new Terminal window, then run: yt-seb song title\n'
printf 'Song info mode:                     yt-seb -si song title\n'
printf 'Uninstall:                          yt-seb-uninstall\n'
