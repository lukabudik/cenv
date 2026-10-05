#!/usr/bin/env bash
# cenv installer. Idempotent; never touches ~/.claude or any env's contents.
#
#   ./install.sh                 from a clone
#   curl -fsSL https://raw.githubusercontent.com/lukabudik/cenv/main/install.sh | bash
#
# Options:
#   --rc <file>   shell rc file to hook into (default: ~/.zshrc or ~/.bashrc from $SHELL)
#   --no-rc       install files only, don't edit any rc file
set -euo pipefail

REPO_RAW="${CENV_REPO_RAW:-https://raw.githubusercontent.com/lukabudik/cenv/main}"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/cenv"
rc=""; edit_rc=1

while [ $# -gt 0 ]; do
  case "$1" in
    --rc) rc="$2"; shift 2 ;;
    --no-rc) edit_rc=0; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

src=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/cenv.sh" ]; then
  src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

fetch() {  # fetch <name> <dest>
  if [ -n "$src" ]; then cp "$src/$1" "$2"
  else curl -fsSL "$REPO_RAW/$1" -o "$2"
  fi
}

mkdir -p "$DEST"
fetch cenv.sh "$DEST/cenv.sh"
fetch statusline.sh  "$DEST/statusline.sh"
chmod +x "$DEST/statusline.sh"
echo "installed  $DEST/cenv.sh"
echo "installed  $DEST/statusline.sh"

if [ -f "$DEST/config" ]; then
  echo "kept       $DEST/config (already exists)"
else
  fetch config.example "$DEST/config"
  echo "created    $DEST/config  <- edit this: your envs and folder rules"
fi

if [ "$edit_rc" = 1 ]; then
  if [ -z "$rc" ]; then
    case "${SHELL:-}" in
      */zsh)  rc="$HOME/.zshrc" ;;
      */bash) rc="$HOME/.bashrc" ;;
      *) echo "Unsupported shell '${SHELL:-?}'. Re-run with --rc <file> (zsh or bash), or source $DEST/cenv.sh yourself." >&2; exit 1 ;;
    esac
  fi
  touch "$rc"
  if grep -q '>>> cenv >>>' "$rc"; then
    echo "kept       hook in $rc (already present)"
  else
    {
      printf '\n# >>> cenv >>>  (pick the Claude Code env from the current directory)\n'
      printf '[ -f "%s/cenv.sh" ] && . "%s/cenv.sh"\n' "${DEST/#$HOME/\$HOME}" "${DEST/#$HOME/\$HOME}"
      printf '# <<< cenv <<<\n'
    } >> "$rc"
    echo "added      hook to $rc"
  fi
  if grep -v '^[[:space:]]*#' "$rc" | grep -q 'CLAUDE_CONFIG_DIR'; then
    echo
    echo "warning: $rc also sets CLAUDE_CONFIG_DIR somewhere. Remove that, or it will fight the directory rules."
  fi
  case "$rc" in
    *bashrc) [ "$(uname)" = Darwin ] && ! grep -qs 'bashrc' "$HOME/.bash_profile" && \
      echo "note: on macOS, bash login shells read ~/.bash_profile; make sure it sources ~/.bashrc." ;;
  esac
fi

cat <<EOF

Next:
  1. Edit $DEST/config
  2. Open a new terminal (or: source $DEST/cenv.sh), then run: cenv list
  3. cd into a folder of each env and run claude once to log in there
  4. Optional status line, in each env's settings.json:
       "statusLine": { "type": "command", "command": "bash $DEST/statusline.sh" }
EOF
