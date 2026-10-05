#!/usr/bin/env bash
# Installer / uninstaller round trip in a throwaway HOME.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
t=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cenv-test.XXXXXX")" && pwd -P)
trap 'rm -rf "${t:?}"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

run() { env -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$t/h" "$@" >"$t/out" 2>&1; }

mkdir -p "$t/h"
run env SHELL=/bin/zsh "$here/install.sh"
check "install creates files" '[ -f "$t/h/.config/cenv/cenv.sh" ] && [ -x "$t/h/.config/cenv/statusline.sh" ] && [ -f "$t/h/.config/cenv/config" ]'
check "install hooks .zshrc"  'grep -q ">>> cenv >>>" "$t/h/.zshrc"'

echo "# my edits" >> "$t/h/.config/cenv/config"
run env SHELL=/bin/zsh "$here/install.sh"
check "re-run keeps config"   'grep -q "# my edits" "$t/h/.config/cenv/config"'
check "re-run adds no 2nd hook" '[ "$(grep -c ">>> cenv >>>" "$t/h/.zshrc")" = 1 ]'

mkdir -p "$t/h/work/acme/x" "$t/h/other"
res=$(env -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$t/h" zsh -c '
  source ~/.zshrc
  cd ~/work/acme/x; echo "${CENV_ACTIVE}:${CLAUDE_CONFIG_DIR-UNSET}"
  cd ~/other;       echo "${CENV_ACTIVE}:${CLAUDE_CONFIG_DIR-UNSET}"')
check "zsh hook switches on cd" '[ "$res" = "work:UNSET
personal:$t/h/.claude-personal" ]'

echo 'export CLAUDE_CONFIG_DIR=~/.claude-x' >> "$t/h/.zshrc"
run env SHELL=/bin/zsh "$here/install.sh"
check "warns on competing CLAUDE_CONFIG_DIR" 'grep -q "^warning" "$t/out"'

run "$here/uninstall.sh"
check "uninstall removes hook"  '! grep -q "cenv" "$t/h/.zshrc"'
check "uninstall keeps config"  '[ -f "$t/h/.config/cenv/config" ]'
check "uninstall keeps other rc lines" 'grep -q "claude-x" "$t/h/.zshrc"'

# piped install (curl | bash), files fetched from REPO_RAW
mkdir -p "$t/h2"
env -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$t/h2" SHELL=/bin/bash \
  CENV_REPO_RAW="file://$here" bash < "$here/install.sh" >"$t/out" 2>&1
check "piped install fetches files" '[ -f "$t/h2/.config/cenv/cenv.sh" ] && [ -f "$t/h2/.config/cenv/config" ]'
check "piped install hooks .bashrc" 'grep -q ">>> cenv >>>" "$t/h2/.bashrc"'
res=$(env -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$t/h2" bash -c 'source ~/.bashrc; mkdir -p ~/work/acme; cd ~/work/acme; eval "$PROMPT_COMMAND"; echo "$CENV_ACTIVE"')
check "bash PROMPT_COMMAND hook" '[ "$res" = work ]'

exit $fail
