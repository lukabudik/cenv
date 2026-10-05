#!/usr/bin/env bash
# Exercises cenv.sh in every available shell against a throwaway HOME.
# Usage: test/run.sh
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

shells=()
for s in zsh /bin/bash bash; do
  p=$(command -v "$s" 2>/dev/null) || continue
  case " ${shells[*]-} " in *" $p "*) ;; *) shells+=("$p") ;; esac
done

for sh in "${shells[@]}"; do
  tmp=$(mktemp -d)
  mkdir -p "$tmp/home/work/acme/repo" "$tmp/home/work/acme-other" "$tmp/home/side" \
           "$tmp/home/.config/cenv" "$tmp/home/.claude-personal"
  cat > "$tmp/home/.config/cenv/config" <<'EOF'
# test config
env   work      ~/.claude            @acme.com
env   personal  ~/.claude-personal

rule  ~/work/acme   work
rule  *             personal
EOF
  printf '{"oauthAccount":{"emailAddress":"me@example.com"}}' > "$tmp/home/.claude-personal/.claude.json"
  ln -s "$tmp/home/work/acme" "$tmp/home/acme-link"

  out=$(HOME="$tmp/home" CLAUDE_CONFIG_DIR= "$sh" -c '
    unset CLAUDE_CONFIG_DIR CENV_ACTIVE CENV_PINNED XDG_CONFIG_HOME CENV_CONFIG
    . "'"$here"'/cenv.sh"
    step() { cd "$1" && _cenv_update; echo "$2 ${CENV_ACTIVE:-none} ${CLAUDE_CONFIG_DIR-UNSET}"; }
    step "$HOME/work/acme/repo"   work_subdir
    step "$HOME/work/acme"        work_root
    step "$HOME/work/acme-other"  sibling_prefix
    step "$HOME/side"             elsewhere
    step "$HOME/acme-link"        via_symlink
    cenv pin work >/dev/null
    step "$HOME/side"             pinned
    cenv unpin >/dev/null
    step "$HOME/side"             unpinned
    echo "which $(cenv which "$HOME/work/acme/x")"
    echo "acct $(cenv | grep account | tr -s " " | cut -d" " -f3)"
    echo "run $(cenv exec work sh -c "echo \${CLAUDE_CONFIG_DIR-UNSET}")"
    echo "after_exec ${CENV_ACTIVE}"
    cenv pin nope 2>/dev/null; echo "badpin $? ${CENV_ACTIVE}"
  ' 2>&1)

  h="$tmp/home"
  expected="work_subdir work UNSET
work_root work UNSET
sibling_prefix personal $h/.claude-personal
elsewhere personal $h/.claude-personal
via_symlink work UNSET
pinned work UNSET
unpinned personal $h/.claude-personal
which work
acct me@example.com
run UNSET
after_exec personal
badpin 1 personal"
  if [ "$out" = "$expected" ]; then
    echo "ok   $sh ($("$sh" -c 'echo ${ZSH_VERSION:-$BASH_VERSION}'))"
  else
    echo "FAIL $sh"; diff <(echo "$expected") <(echo "$out") | sed 's/^/     /'; fail=1
  fi
  rm -rf "$tmp"
done

# Statusline renders and flags an account mismatch.
tmp=$(mktemp -d); mkdir -p "$tmp/.config/cenv" "$tmp/.claude-personal"
printf 'env work ~/.claude @acme.com\nenv personal ~/.claude-personal @example.com\nrule * personal\n' > "$tmp/.config/cenv/config"
printf '{"oauthAccount":{"emailAddress":"me@acme.com"}}' > "$tmp/.claude-personal/.claude.json"
printf '{"oauthAccount":{"emailAddress":"me@acme.com"}}' > "$tmp/.claude.json"
json='{"workspace":{"current_dir":"/tmp/x"},"model":{"display_name":"Claude Opus"},"context_window":{"remaining_percentage":42.4}}'
ok_line=$(echo "$json" | env -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME -u CENV_CONFIG HOME="$tmp" CENV_ACTIVE=work bash "$here/statusline.sh")
bad_line=$(echo "$json" | env -u XDG_CONFIG_HOME -u CENV_CONFIG HOME="$tmp" CENV_ACTIVE=personal CLAUDE_CONFIG_DIR="$tmp/.claude-personal" bash "$here/statusline.sh")
case "$ok_line" in *"work·acme.com"*) case "$ok_line" in *$'\033[35m'*) echo "FAIL statusline: matching account flagged"; fail=1 ;; *) echo "ok   statusline (match)";; esac ;; *) echo "FAIL statusline: $ok_line"; fail=1 ;; esac
case "$bad_line" in *$'\033[35m'*"personal·acme.com"*) echo "ok   statusline (mismatch is magenta)" ;; *) echo "FAIL statusline mismatch: $bad_line"; fail=1 ;; esac
rm -rf "$tmp"

exit $fail
