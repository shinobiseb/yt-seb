#!/usr/bin/env bash

set -euo pipefail
umask 077

case "${HOME:-}" in /*) ;; *) printf '%s\n' 'Error: HOME must be an absolute path.' >&2; exit 1 ;; esac
[ "$(uname -s)" = 'Darwin' ] || { printf '%s\n' 'Error: this uninstaller supports macOS only.' >&2; exit 1; }

APP_DIR="$HOME/.local/share/yt-seb"
BIN_DIR="$HOME/.local/bin"
[ ! -L "$APP_DIR" ] || { printf '%s\n' "Error: refusing symlinked install path: $APP_DIR" >&2; exit 1; }
[ -f "$APP_DIR/.yt-seb-macos-install" ] || {
  printf '%s\n' "Error: $APP_DIR is not a recognized yt-seb installation." >&2
  exit 1
}

printf '%s' 'Remove yt-seb from this user account? Music files will be kept. [y/N] '
IFS= read -r answer
case "$answer" in y|Y|yes|YES) ;; *) printf '%s\n' 'Uninstall cancelled.'; exit 0 ;; esac

remove_path_block() {
  local profile=$1 temporary begin_count end_count
  [ -f "$profile" ] || return 0
  [ ! -L "$profile" ] || { printf '%s\n' "Warning: leaving symlinked profile unchanged: $profile" >&2; return 0; }
  begin_count="$(grep -Fxc '# >>> yt-seb >>>' "$profile" || true)"
  end_count="$(grep -Fxc '# <<< yt-seb <<<' "$profile" || true)"
  if [ "$begin_count" -eq 0 ] && [ "$end_count" -eq 0 ]; then return 0; fi
  if [ "$begin_count" -ne 1 ] || [ "$end_count" -ne 1 ]; then
    printf '%s\n' "Warning: leaving malformed yt-seb PATH markers unchanged in $profile" >&2
    return 0
  fi
  temporary="${profile}.yt-seb.tmp.$$"
  if ! awk '
    $0 == "# >>> yt-seb >>>" { removing=1; next }
    $0 == "# <<< yt-seb <<<" { if (!removing) exit 2; removing=0; complete=1; next }
    !removing { print }
    END { if (removing || !complete) exit 2 }
  ' "$profile" > "$temporary"; then
    rm -f -- "$temporary"
    printf '%s\n' "Warning: leaving malformed yt-seb PATH markers unchanged in $profile" >&2
    return 0
  fi
  cat "$temporary" > "$profile"
  rm -f -- "$temporary"
}

if [ -f "$BIN_DIR/yt-seb" ] && grep -Fq '# yt-seb macOS command' "$BIN_DIR/yt-seb"; then
  rm -f -- "$BIN_DIR/yt-seb"
elif [ -e "$BIN_DIR/yt-seb" ] || [ -L "$BIN_DIR/yt-seb" ]; then
  printf '%s\n' "Warning: leaving unrecognized command unchanged: $BIN_DIR/yt-seb" >&2
fi
if [ -L "$BIN_DIR/yt-seb-uninstall" ] && \
  [ "$(readlink "$BIN_DIR/yt-seb-uninstall")" = "$APP_DIR/uninstall-macos.sh" ]; then
  rm -f -- "$BIN_DIR/yt-seb-uninstall"
elif [ -e "$BIN_DIR/yt-seb-uninstall" ] || [ -L "$BIN_DIR/yt-seb-uninstall" ]; then
  printf '%s\n' "Warning: leaving unrecognized command unchanged: $BIN_DIR/yt-seb-uninstall" >&2
fi
remove_path_block "$HOME/.zprofile"
remove_path_block "$HOME/.bash_profile"
rm -rf -- "$APP_DIR"

printf '%s\n' 'yt-seb was removed. Downloaded music was not deleted.'
