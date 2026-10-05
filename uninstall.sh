#!/usr/bin/env bash
# Removes the cenv hook and scripts. Leaves your config and every Claude
# config dir (~/.claude, ~/.claude-*) untouched — your envs and logins stay.
set -euo pipefail
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/cenv"

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  if [ ! -f "$rc" ] || ! grep -q '>>> cenv >>>' "$rc"; then continue; fi
  cp "$rc" "$rc.bak-cenv"
  sed -i.tmp '/^# >>> cenv >>>/,/^# <<< cenv <<</d' "$rc" && rm -f "$rc.tmp"
  echo "removed hook from $rc (backup: $rc.bak-cenv)"
done

rm -f "$DEST/cenv.sh" "$DEST/statusline.sh"
echo "removed scripts from $DEST (config kept)"
echo "If an env's settings.json points statusLine at $DEST/statusline.sh, remove that entry."
echo "Open a new terminal: claude will use ~/.claude everywhere again."
