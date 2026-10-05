# Claude desktop app: a second env (experimental)

> **Status: untested end to end. Testers wanted.** Everything below comes from reading the
> desktop app's code (v1.14271, macOS) and a test launch. Nobody has yet logged in to a
> second copy and confirmed its Code tab uses the other env. If you try it, please
> [open an issue](https://github.com/lukabudik/cenv/issues) with what you saw.

cenv's hook only works in terminals. The desktop app never runs your shell hook, and it
opens projects itself, so it can't switch envs **by folder**. What looks possible is
running **one copy of the app per env**, side by side, each with its own login and its
own Claude Code config.

## What we know

| Finding | How we know |
|---|---|
| The Code tab loads your login-shell environment but **drops `CLAUDE_CONFIG_DIR` from it** on purpose. Only the value the app itself was launched with counts. | App code |
| The app's own launch environment is passed on to Code tab sessions, including `CLAUDE_CONFIG_DIR`. | App code |
| `CLAUDE_USER_DATA_DIR` moves the app's whole profile: claude.ai login, cookies, app settings. **Undocumented.** | App code + test launch: the new profile folder was created and started logged out |
| Two copies can run at the same time. | Test launch |

Why both variables are needed: the Code tab most likely signs in with the **desktop app's
own claude.ai login**, not the CLI login stored in the config dir. So the separate profile
(`CLAUDE_USER_DATA_DIR`) carries the account, and `CLAUDE_CONFIG_DIR` carries plugins,
MCP servers, skills, settings and history. This split is inferred, not confirmed.

## Try it

Keep your normal app as the env that lives in `~/.claude` (usually work). Start a second
copy for the other env:

```bash
open -n -a Claude \
  --env CLAUDE_USER_DATA_DIR="$HOME/Library/Application Support/Claude-personal" \
  --env CLAUDE_CONFIG_DIR="$HOME/.claude-personal"
```

- `-n` starts a new copy even if Claude is already running.
- Use the config dir from your cenv config (`cenv list`).
- Log in to this copy with the account for that env. You do this once; the profile
  folder keeps the login.
- Start it with this same command every time. Opening Claude from the Dock or Spotlight
  starts your normal profile.

### Optional: a launcher in Spotlight and the Dock

```bash
osacompile -o ~/Applications/"Claude (personal).app" -e \
  'do shell script "open -n -a Claude --env CLAUDE_USER_DATA_DIR=\"$HOME/Library/Application Support/Claude-personal\" --env CLAUDE_CONFIG_DIR=\"$HOME/.claude-personal\""'

# Give it Claude's icon (optional)
cp /Applications/Claude.app/Contents/Resources/electron.icns \
   ~/Applications/"Claude (personal).app"/Contents/Resources/applet.icns
codesign --force --sign - ~/Applications/"Claude (personal).app"
```

The launcher only starts the second copy and exits. The running app still appears in the
Dock as a second, identical Claude icon.

## How to verify (please report these)

With the second copy logged in, open a **Code** session in any folder, then check:

1. **Config dir.** Ask Claude to run `echo "${CLAUDE_CONFIG_DIR:-unset}"`. Expected:
   `/Users/you/.claude-personal`.
2. **History lands in the right env.** After the session, a new folder should appear under
   `~/.claude-personal/projects/` and nothing new under `~/.claude/projects/`.
3. **Plugins and MCP.** `/mcp` and the skills list should show the personal env's servers
   and plugins, not the work ones.
4. **Account.** Usage should count against the account you logged in to in this copy.
   Note which account the Code tab uses if the app login and the env's CLI login differ.
5. **Both copies at once.** The normal copy should keep using `~/.claude` and the work
   account.

Please include the app version (Claude → About Claude) in the issue.

## Known caveats

- **Undocumented.** `CLAUDE_USER_DATA_DIR` isn't a public setting. An app update could
  change or remove it.
- **Not by folder.** You choose the env by which copy of the app you open the project in.
- **Two identical Dock icons.** Hard to tell apart at a glance; the window's account menu
  shows which is which.
- **`claude://` links and "Open in Claude"** go to whichever copy macOS picks.
- **Auto-update** with two copies running hasn't been tested. If something looks off after
  an update, quit both and start again.
- **macOS only** so far. Windows has its own handling of these variables in the app and
  hasn't been looked at.

## Undo

Quit the second copy, then delete its profile folder and the launcher:

```bash
rm -rf ~/Library/Application\ Support/Claude-personal ~/Applications/"Claude (personal).app"
```

This doesn't touch `~/.claude-personal` or your normal desktop app.
