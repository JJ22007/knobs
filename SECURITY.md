# Security

Knobs changes settings on your Mac, and an agent may be the one asking. This page says what it can touch, what it keeps on disk, and how to report a problem.

## What Knobs changes

- **macOS preferences in your own account.** Every setting in `knobs list` names the exact preference domain and key it writes (`knobs get <id>` shows it). Knobs writes through CFPreferences as you, reads the value back, and never uses `sudo`, never asks for an administrator password and never touches system-wide or other users' preferences.
- **Dock, Finder and other system UI processes** are restarted with `killall` only when a value they read at launch actually changed. launchd starts them again straight away.
- **Live features** run inside the Knobs app while it is open: keeping the display or the Mac awake (an IOKit power assertion, the same mechanism as `caffeinate`) and instant Space switching (needs the Accessibility permission, which only you can grant in System Settings). Quitting Knobs ends them.
- **A few files you ask for.** A profile may replace one companion file, `~/.config/paneful/config.json` (the old copy is kept as `.bak`). `knobs export <file>` writes where you tell it. The Claude Code skill goes to `~/.claude/skills/knobs/SKILL.md` only when you say yes during `build.sh install` or run `knobs skill install`. Installing puts the app in `~/Applications` and a `knobs` link in `~/.local/bin`. Apart from these and `~/.config/knobs`, Knobs writes no files.
- **Other tools, only through their own interfaces.** A scene may set brightness through `overbright mcp` and arrange windows through `paneful mcp`. Knobs never edits their files.

## What Knobs keeps on disk

Everything stays in `~/.config/knobs` on this Mac:

- `backups/`: a snapshot taken before every change, so `knobs undo` can step back. At most 50 are kept. Each file is created owner-only (`0600`), because a snapshot may hold the window titles of a saved Paneful layout.
- `config.json`: shortcuts and app preferences.
- `status.json`: the state of live features, so the command line can confirm them.

Knobs has no analytics, no crash reporter and no account. It goes online only when you give `knobs apply` an `https://` link, and then it downloads that one file (plain `http://` is refused). `knobs export` writes your home folder as `~/` and the self-test checks that an export carries neither the home folder nor the account name.

## Agents and MCP

- `knobs mcp` is **read-only by default.** Writes need `knobs mcp --allow-write`, which only you can put in your MCP client's configuration. Dry runs are always allowed.
- Every write saves a snapshot first and returns the value read back from macOS, so an agent cannot quietly claim a change it did not make, and `undo` puts it back.
- A batch of changes is all or nothing: one refused value means nothing was written.
- Paths in command and MCP output use `~` rather than your home folder, and window results name only the app, not the window title.

## Reporting a security problem

Please do not put details of a vulnerability in a public issue. Instead, open an issue titled **"Security contact request"** with no details, and the maintainer will reply with a private way to send them. Reports about Knobs writing something it did not list, writing outside your account, or an agent getting a write through a read-only `knobs mcp` are especially welcome.

Knobs is built from source on your Mac and is not notarized yet. Only the latest version on `main` gets fixes.
