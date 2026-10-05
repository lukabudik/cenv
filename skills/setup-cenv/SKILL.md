---
name: setup-cenv
description: Set up separate Claude Code environments (e.g. work and personal) that switch automatically by folder — each with its own login, settings, plugins, MCP servers, skills and history. Use when the user wants a work/personal split, multiple Claude accounts by directory, per-folder CLAUDE_CONFIG_DIR, or asks to install cenv. Also handles adding another env or rule to an existing cenv setup.
---

# Set up cenv

Goal: the user ends with N Claude Code environments, picked automatically by the directory
they launch `claude` from, each logged in to the right account. Tool: cenv
(https://github.com/lukabudik/cenv) — a ~200-line shell hook that sets or unsets
`CLAUDE_CONFIG_DIR` on every `cd`, plus an optional status line.

## How it works (explain briefly if asked)

- `CLAUDE_CONFIG_DIR` relocates everything Claude Code stores: settings.json, plugins,
  user-scope MCP servers (`.claude.json`), skills, agents, commands, CLAUDE.md, history,
  and the login. Each config dir is a fully separate environment.
- cenv maps folders to envs (`rule ~/work/acme work`) and envs to dirs
  (`env work ~/.claude`). A zsh `chpwd` hook / bash `PROMPT_COMMAND` applies it.
- claude.ai connectors and org-managed settings follow the **logged-in account**, not the
  folder — so logging each env into the right account is what brings them along.

## Hard rules

- **Never delete, move or rewrite `~/.claude` or `~/.claude.json`.** Users keep their
  existing environment as one of the envs, untouched.
- **Never `export CLAUDE_CONFIG_DIR=$HOME/.claude`** (or put it in any file). On macOS the
  Keychain entry name is derived from the raw variable value, so the explicit default path
  reads as logged out. The env living in `~/.claude` is selected by *unsetting* the
  variable; cenv does this for you.
- Never print credentials, tokens or Keychain secrets. Only check that entries exist.
- Before overwriting any existing file (settings.json, a skills dir, the cenv
  config), show what is there and get a yes. Back up with a `.bak-cenv` suffix.
- This session itself runs inside one env and its shell may have `CLAUDE_CONFIG_DIR`
  set. When inspecting a specific env, be explicit: `env -u CLAUDE_CONFIG_DIR <cmd>` for
  `~/.claude`, `CLAUDE_CONFIG_DIR=<dir> <cmd>` for others.

## 1. Inspect (no changes yet)

Run and summarise for the user in a short table:

```bash
uname -s; echo "$SHELL"; claude --version
echo "CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR-<unset>}"
ls -d ~/.claude ~/.claude-* 2>/dev/null
jq -r '.oauthAccount.emailAddress // "not logged in"' ~/.claude.json 2>/dev/null
for d in ~/.claude-*/; do [ -f "$d.claude.json" ] && echo "$d: $(jq -r '.oauthAccount.emailAddress // "not logged in"' "$d.claude.json")"; done
ls ~/.config/cenv/ 2>/dev/null && cat ~/.config/cenv/config
grep -n 'CLAUDE_CONFIG_DIR\|cenv' ~/.zshrc ~/.bashrc ~/.bash_profile ~/.zprofile 2>/dev/null
jq '{statusLine, enabledPlugins: (.enabledPlugins|keys?)}' ~/.claude/settings.json 2>/dev/null
ls -d ~/work ~/code ~/projects ~/dev ~/src ~/Developer 2>/dev/null
```

Stop and tell the user if:
- The shell is not zsh or bash (fish, PowerShell): cenv doesn't support it yet.
  On Windows, it works inside WSL only.
- `cenv` is already installed: switch to *adding* envs/rules to the existing
  config rather than reinstalling.
- An rc file already exports `CLAUDE_CONFIG_DIR` or defines claude aliases: those must be
  removed (with the user's OK) or they will fight the hook.

## 2. Ask (one round, AskUserQuestion)

Propose defaults from what you found; don't make the user design it from scratch.

1. **Which env keeps the existing `~/.claude`?** Recommend: the env matching the account
   already logged in there (usually work — the company account's managed settings,
   plugins and history stay exactly as they are). The other env gets a new dir
   `~/.claude-<name>`.
2. **Folder rules.** Which folder(s) belong to which env, and which env is the catch-all
   `*` for everywhere else. Typical: `~/work/<company>` → work, `*` → personal. Suggest
   real folders you found. Most-specific rules first.
3. **Expected accounts** (optional): an email domain per env, e.g. `@acme.com`. The status
   line turns magenta when an env is logged in to the wrong account.
4. **Share anything between envs?** Options: nothing (fully separate — safest default for
   a work/personal split); or symlink selected items from the new env to `~/.claude`:
   `CLAUDE.md` (personal instructions), `skills/`, `agents/`, `commands/`. Warn that
   anything shared is visible to both accounts' sessions — don't share if work skills or
   instructions contain anything confidential.
5. **Status line:** install cenv's status line in envs that don't have one? For envs
   that already have one, offer the `--badge` mode to prepend instead of replacing.
6. **Account swapping** (optional): do they want to swap accounts *inside* an env without
   losing its plugins, MCP servers and history — e.g. keep working in the work env on a
   personal account when they hit a limit? If yes, set up claude-swap (step 3.7).

## 3. Install

1. Write `~/.config/cenv/config` (format in `config.example` of the repo):
   ```
   env   work      ~/.claude            @acme.com
   env   personal  ~/.claude-personal   @gmail.com

   rule  ~/work/acme   work
   rule  *             personal
   ```
   Show it to the user before writing.
2. Run the installer. Find it in this order:
   - the plugin's own copy:
     `ls "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/cenv/cenv/*/install.sh ~/.claude*/plugins/cache/cenv/cenv/*/install.sh 2>/dev/null | head -1`
   - a local clone the user points you to
   - `curl -fsSL https://raw.githubusercontent.com/lukabudik/cenv/main/install.sh | bash`

   It is idempotent, keeps an existing config, and appends a marked block to the rc file.
3. Create the new env dir(s): `mkdir -p ~/.claude-<name>`.
4. Sharing (if chosen), for each item: if the target exists in the new env, show it and
   ask; otherwise `ln -s ~/.claude/<item> ~/.claude-<name>/<item>`.
5. Status line (if chosen), per env, with `jq` into that env's `settings.json`
   (create `{}` if missing; back up first):
   `"statusLine": {"type": "command", "command": "bash ~/.config/cenv/statusline.sh"}`
6. Optional seed: if the user wants their cosmetic preferences carried over, copy only
   `theme`, `model`, `editorMode` and `statusLine` into the new env's settings.json. Never
   copy `permissions`, `hooks`, `env`, `enabledPlugins` or MCP config wholesale — those are
   per-env on purpose; set them up fresh in the new env.
7. Account swapping (if chosen): install claude-swap if `cswap` is missing
   (`uv tool install claude-swap`, or `pipx install claude-swap`). Registering accounts
   needs interactive logins, so hand it over in step 5. Never run `cswap run`: it creates
   a separate environment of its own, which defeats the point.

## 4. Verify

Use a fresh shell so the rc hook is what's being tested:

```bash
zsh -ic 'cenv list'            # or bash -ic
zsh -ic 'cd ~/work/acme && cenv; cd ~ && cenv'   # use the user's real folders
```

Each folder must report the intended env. The env living in `~/.claude` must show
`config ~/.claude` with `CLAUDE_CONFIG_DIR` unset.

## 5. Hand over to the user

The login can't be done from here (it is interactive). Tell them, concretely:

1. Open a **new terminal** (the hook loads from the rc file).
2. `cd` into a folder of the new env, run `claude`, and log in with that env's account
   (`/login` if it doesn't prompt). `cenv list` then shows both accounts.
3. Add MCP servers and plugins per env by running them from a folder of that env, e.g.
   `claude mcp add -s user ...` or `/plugin` inside a session. From anywhere:
   `cenv exec personal claude mcp add -s user ...`.
4. Cheat sheet: `cenv` (where am I), `cenv list`, `cenv pin <env>` / `cenv unpin`
   (override for one terminal tab), `cenv run <env>` (launch once in an env),
   `cenv edit` (change rules).
5. Account swapping (if set up): in a folder of the env, `cswap add` registers the account
   logged in now; `/login` with the other account in `claude`, then `cswap add` again.
   After that `cswap switch <email|number>` swaps accounts. Plain `cswap` acts on the
   current folder's env because it reads `CLAUDE_CONFIG_DIR`; from elsewhere use
   `cenv exec <env> cswap ...`. Restart sessions after a swap. Plugins, MCP servers and
   their logins, skills and history stay; claude.ai connectors and org-managed settings
   change with the account. The status line turns magenta while the account doesn't match
   the env's `expected-account`.

## Gotchas to mention when relevant

- **Terminal only.** The hook runs in shells. The VS Code / JetBrains extensions and the
  desktop app use whatever environment they were launched with; the integrated terminal
  in VS Code does run the hook.
- **Restart sessions after changing accounts** — the credential is read at startup.
- **MCP OAuth is per env and per server name.** A server added in one env must be added
  and authorised again in the other.
- **claude.ai connectors and org-managed settings/plugins follow the account**, not the
  folder. They can't be copied into another env; logging in brings them.
- **Project `.claude/settings.json` and `.mcp.json` still apply in both envs** — they
  belong to the repo, not the env.
- **Environment vs. account.** cenv picks the environment by folder; claude-swap
  ([realiti4/claude-swap](https://github.com/realiti4/claude-swap)) swaps the account
  inside it. They are separate tools that combine without extra wiring.
