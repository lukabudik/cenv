# cenv — pick a Claude Code environment from the current directory.
#
# Source this from ~/.zshrc or ~/.bashrc. Every time you change directory it
# sets (or unsets) CLAUDE_CONFIG_DIR according to the rules in your config, so
# `claude` launched from that directory gets that environment's settings,
# plugins, MCP servers, skills, history and login.
#
# Config: ${XDG_CONFIG_HOME:-~/.config}/cenv/config  (see config.example)
# Works in zsh and bash (3.2+). No dependencies.
#
# Gotcha baked in: the environment that lives in ~/.claude is selected by
# *unsetting* CLAUDE_CONFIG_DIR, never by exporting it. On macOS Claude Code
# derives its Keychain entry name from the raw variable value, so an explicit
# CLAUDE_CONFIG_DIR=~/.claude looks for a different entry and reads as logged out.

: "${CENV_CONFIG:=${XDG_CONFIG_HOME:-$HOME/.config}/cenv/config}"

# ~ → $HOME, drop a trailing slash. Result in REPLY.
_cenv_expand() {
  # shellcheck disable=SC2088  # matching a literal "~/" from the config is the point
  case "$1" in
    "~")   REPLY="$HOME" ;;
    "~/"*) REPLY="$HOME/${1#"~/"}" ;;
    *)     REPLY="$1" ;;
  esac
  while :; do
    case "$REPLY" in *//*) REPLY="${REPLY%%//*}/${REPLY#*//}" ;; *) break ;; esac
  done
  case "$REPLY" in /) ;; */) REPLY="${REPLY%/}" ;; esac
}

# Config dir of env $1. Result in REPLY; fails for an unknown env.
_cenv_dir() {
  local kind a b rest
  [ -r "$CENV_CONFIG" ] || return 1
  while read -r kind a b rest || [ -n "$kind" ]; do
    [ "$kind" = env ] && [ "$a" = "$1" ] || continue
    _cenv_expand "$b"
    return 0
  done < "$CENV_CONFIG"
  return 1
}

# Optional expected-account pattern of env $1 (4th column). Result in REPLY.
_cenv_expect() {
  local kind a b c rest
  REPLY=""
  [ -r "$CENV_CONFIG" ] || return 1
  while read -r kind a b c rest || [ -n "$kind" ]; do
    [ "$kind" = env ] && [ "$a" = "$1" ] || continue
    REPLY="$c"
    return 0
  done < "$CENV_CONFIG"
  return 1
}

# Env for directory $1 (first matching rule wins). Result in REPLY.
# Tries the path as given, then with symlinks resolved, before the `*` rule.
_cenv_match() {
  local kind a b rest dir phys=""
  [ -r "$CENV_CONFIG" ] || return 1
  _cenv_expand "$1"; dir="$REPLY"
  if [ -n "${ZSH_VERSION:-}" ]; then
    phys="${dir:A}"
  elif [ -d "$dir" ]; then
    phys=$(cd "$dir" 2>/dev/null && pwd -P)
  fi
  [ "$phys" = "$dir" ] && phys=""
  while read -r kind a b rest || [ -n "$kind" ]; do
    [ "$kind" = rule ] || continue
    if [ "$a" = "*" ]; then REPLY="$b"; return 0; fi
    _cenv_expand "$a"
    case "$dir/" in "$REPLY"/*) REPLY="$b"; return 0 ;; esac
    if [ -n "$phys" ]; then
      case "$phys/" in "$REPLY"/*) REPLY="$b"; return 0 ;; esac
      # the rule path itself may sit behind a symlink
      if [ -n "${ZSH_VERSION:-}" ]; then REPLY="${REPLY:A}"
      elif [ -d "$REPLY" ]; then REPLY=$(cd "$REPLY" 2>/dev/null && pwd -P)
      fi
      case "$phys/" in "$REPLY"/*) REPLY="$b"; return 0 ;; esac
    fi
  done < "$CENV_CONFIG"
  return 1
}

# Point this shell at env $1.
_cenv_apply() {
  local name="$1"
  if ! _cenv_dir "$name"; then
    echo "cenv: unknown env '$name' (check $CENV_CONFIG)" >&2
    return 1
  fi
  if [ "$REPLY" = "$HOME/.claude" ]; then
    unset CLAUDE_CONFIG_DIR
  else
    export CLAUDE_CONFIG_DIR="$REPLY"
  fi
  export CENV_ACTIVE="$name"
}

# The hook: re-evaluate for $PWD unless this shell is pinned.
_cenv_update() {
  [ -n "${CENV_PINNED:-}" ] && return 0
  [ "${_CENV_LAST_PWD:-}" = "$PWD" ] && return 0
  _CENV_LAST_PWD="$PWD"
  if _cenv_match "$PWD"; then
    _cenv_apply "$REPLY"
  else
    unset CLAUDE_CONFIG_DIR CENV_ACTIVE
  fi
}

# Global config file (holds the logged-in account) for config dir $1.
_cenv_global_json() {
  if [ "$1" = "$HOME/.claude" ]; then REPLY="$HOME/.claude.json"; else REPLY="$1/.claude.json"; fi
}

# Logged-in email for config dir $1, or empty. Result in REPLY.
_cenv_account() {
  local file
  _cenv_global_json "$1"; file="$REPLY"; REPLY=""
  [ -r "$file" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    REPLY=$(jq -r '.oauthAccount.emailAddress // empty' "$file" 2>/dev/null)
  else
    REPLY=$(sed -n 's/.*"emailAddress": *"\([^"]*\)".*/\1/p' "$file" | head -n 1)
  fi
  [ -n "$REPLY" ]
}

cenv() {
  local cmd="${1:-status}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    status|"")
      local dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" why="directory rule"
      [ -n "${CENV_PINNED:-}" ] && why="pinned"
      [ -z "${CENV_ACTIVE:-}" ] && why="no rule matched, Claude Code default"
      _cenv_account "$dir"
      printf '  env      %s (%s)\n' "${CENV_ACTIVE:-default}" "$why"
      printf '  config   %s\n' "$dir"
      printf '  account  %s\n' "${REPLY:-not logged in}"
      ;;
    list|ls)
      local kind a b c rest marker acct
      [ -r "$CENV_CONFIG" ] || { echo "cenv: no config at $CENV_CONFIG" >&2; return 1; }
      echo "envs:"
      while read -r kind a b c rest || [ -n "$kind" ]; do
        [ "$kind" = env ] || continue
        _cenv_expand "$b"; local d="$REPLY"
        _cenv_account "$d"; acct="${REPLY:-not logged in}"
        marker=" "; [ "$a" = "${CENV_ACTIVE:-}" ] && marker="*"
        printf '  %s %-12s %-28s %s\n' "$marker" "$a" "$b" "$acct"
      done < "$CENV_CONFIG"
      echo "rules (first match wins):"
      while read -r kind a b rest || [ -n "$kind" ]; do
        [ "$kind" = rule ] && printf '    %-40s -> %s\n' "$a" "$b"
      done < "$CENV_CONFIG"
      ;;
    which)
      _cenv_expand "${1:-$PWD}"
      local target="$REPLY"
      case "$target" in /*) ;; *) target="$PWD/$target" ;; esac
      if _cenv_match "$target"; then echo "$REPLY"; else echo "default (no rule)"; fi
      ;;
    pin)
      [ -n "${1:-}" ] || { echo "usage: cenv pin <env>" >&2; return 1; }
      _cenv_apply "$1" || return 1
      export CENV_PINNED=1
      echo "pinned to $1 (cenv unpin to let the directory decide)"
      ;;
    unpin)
      unset CENV_PINNED _CENV_LAST_PWD
      _cenv_update
      echo "unpinned: ${CENV_ACTIVE:-default}"
      ;;
    run)
      [ -n "${1:-}" ] || { echo "usage: cenv run <env> [claude args...]" >&2; return 1; }
      local name="$1"; shift
      [ "${1:-}" = "--" ] && shift
      ( _cenv_apply "$name" && command claude "$@" )
      ;;
    exec)
      # cenv exec <env> <command...> — run any command (e.g. claude mcp add, cswap) against an env
      [ -n "${1:-}" ] && [ -n "${2:-}" ] || { echo "usage: cenv exec <env> <command...>" >&2; return 1; }
      local name="$1"; shift
      ( _cenv_apply "$name" && "$@" )
      ;;
    edit)
      "${EDITOR:-vi}" "$CENV_CONFIG" && { unset _CENV_LAST_PWD; _cenv_update; }
      ;;
    help|-h|--help)
      cat <<'EOF'
cenv                      show the active env, its config dir and account
cenv list                 list envs (with logged-in accounts) and rules
cenv which [dir]          which env a directory maps to
cenv pin <env>            pin this shell to an env, ignoring directory rules
cenv unpin                let the directory decide again
cenv run <env> [args]     launch claude once in <env>
cenv exec <env> <cmd...>  run any command against <env> (claude mcp add, cswap, ...)
cenv edit                 edit the rules
EOF
      ;;
    *) echo "cenv: unknown command '$cmd' (try cenv help)" >&2; return 1 ;;
  esac
}

# Install the hook.
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -Uz add-zsh-hook
  add-zsh-hook chpwd _cenv_update
elif [ -n "${BASH_VERSION:-}" ]; then
  case ";${PROMPT_COMMAND:-};" in
    *";_cenv_update;"*) ;;
    *) PROMPT_COMMAND="_cenv_update${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
  esac
fi
_cenv_update
