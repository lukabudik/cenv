#!/usr/bin/env bash
# cenv status line: env·account | dir | git branch | model | context left
#
#   personal·example.com | my-repo | main* | Opus 5.5 | ctx:64%
#
# The env·account badge turns magenta when the logged-in account does not match
# the env's expected-account pattern (4th column of an `env` line in the config),
# e.g. you are in the work env but logged in with your personal account.
#
# Wire it up in each env's settings.json:
#   "statusLine": { "type": "command", "command": "bash ~/.config/cenv/statusline.sh" }
# Already have a status line? Keep it and prepend the output of
#   bash ~/.config/cenv/statusline.sh --badge

input=$(cat)
config="${CENV_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cenv/config}"

DIM='\033[2m'; CYAN='\033[36m'; YELLOW='\033[33m'; GREEN='\033[32m'
RED='\033[31m'; MAGENTA='\033[35m'; RESET='\033[0m'

jget() { command -v jq >/dev/null 2>&1 && printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null; }

# --- env + account ---
cfg_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then gjson="$CLAUDE_CONFIG_DIR/.claude.json"; else gjson="$HOME/.claude.json"; fi
env_name="${CENV_ACTIVE:-}"
if [ -z "$env_name" ]; then
  env_name=$(basename "$cfg_dir"); env_name="${env_name#.claude}"; env_name="${env_name#-}"
  [ -z "$env_name" ] && env_name="default"
fi
email=""
if [ -r "$gjson" ]; then
  if command -v jq >/dev/null 2>&1; then
    email=$(jq -r '.oauthAccount.emailAddress // empty' "$gjson" 2>/dev/null)
  else
    email=$(sed -n 's/.*"emailAddress": *"\([^"]*\)".*/\1/p' "$gjson" | head -n 1)
  fi
fi
acct="${email#*@}"; [ -z "$email" ] && acct="?"

expect=""
if [ -r "$config" ]; then
  while read -r kind a _ c rest || [ -n "$kind" ]; do
    [ "$kind" = env ] && [ "$a" = "$env_name" ] && { expect="$c"; break; }
  done < "$config"
fi
badge_color="$DIM"
if [ -n "$expect" ]; then
  case "$email" in *"$expect"*) ;; *) badge_color="$MAGENTA" ;; esac
fi
badge="${badge_color}${env_name}·${acct}${RESET}"

if [ "${1:-}" = "--badge" ]; then printf '%b' "$badge"; exit 0; fi

# --- the rest ---
cwd=$(jget "$input" '.workspace.current_dir // .cwd'); [ -z "$cwd" ] && cwd="$PWD"
dir=$(basename "$cwd"); [ "$cwd" = "$HOME" ] && dir="~"

branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
if [ -n "$branch" ] && [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null | head -n 1)" ]; then
  branch="${branch}*"
fi

model=$(jget "$input" '.model.display_name'); model="${model#Claude }"
ctx=$(jget "$input" '.context_window.remaining_percentage')

line="$badge${DIM} | ${RESET}${CYAN}${dir}${RESET}"
[ -n "$branch" ] && line="$line${DIM} | ${RESET}${YELLOW}${branch}${RESET}"
[ -n "$model" ] && line="$line${DIM} | ${model}${RESET}"
if [ -n "$ctx" ]; then
  ctx=$(printf '%.0f' "$ctx"); color="$GREEN"; [ "$ctx" -le 20 ] && color="$RED"
  line="$line${DIM} | ${RESET}${color}ctx:${ctx}%${RESET}"
fi
printf '%b\n' "$line"
