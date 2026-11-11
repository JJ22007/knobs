<h1 align="center">Knobs</h1>

<p align="center">
  <b>Every macOS setting worth changing, in one readable list.</b><br>
  Flip a switch and it takes effect now. Let your agent flip it for you. Take the whole setup to your next Mac in one file.
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="#install">Install</a> ·
  <a href="#what-it-controls">Settings</a> ·
  <a href="#let-an-agent-drive">Agents</a> ·
  <a href="#move-to-a-new-mac">New Mac</a>
</p>

<p align="center">
  <img src="docs/demo.gif" width="100%" alt="An AI agent keeps the display awake, turns off window animations and exports the setup">
</p>
<p align="center"><sub>One sentence to Claude Code (Haiku), and Knobs changes live, then exports the setup for the next Mac. Real run; the seconds the agent spends thinking are shortened.</sub></p>

Knobs is a small menu bar app with a settings window and a `knobs` command. It collects the tweaks developers usually paste from dotfiles (`defaults write …`, `pmset …`, yabai) and gives each one a name, an explanation, a switch, and an honest note about when it takes effect.

## Why

- **No animation when switching Spaces, without disabling SIP.** Turn it on and your next `⌃←` / `⌃→` jumps straight to the desktop. Turn it off and the very next press slides again. No restart, no logout.
- **Keep the display awake without `sudo`.** One switch, instant, and it gives your normal sleep timer back when you turn it off.
- **Readable.** Over 90 settings in 13 groups, each with a plain description and the exact preference key behind it. Nothing is hidden in a shell script.
- **Agent-ready.** `knobs list --json` tells an agent what every setting means; `knobs set` changes it. "Make my Mac feel faster" becomes a conversation.
- **Portable.** `knobs export` writes one file. On a new Mac, hand that file to an agent and you get the same settings and the same shortcuts.

## Install

Requires macOS 13 or later and the Swift compiler (`xcode-select --install` if you have never installed it).

```bash
git clone https://github.com/JJ22007/knobs.git
cd knobs
bash build.sh install
```

This builds the app, runs the self-test, installs `Knobs.app` into `~/Applications`, links the `knobs` command into `~/.local/bin`, and opens the window.

### The one permission

Only instant Space switching needs a permission: **Accessibility**, because Knobs has to catch your Space shortcut before macOS starts its animation. Switch Knobs on under System Settings → Privacy & Security → Accessibility. It starts working the moment you do. Everything else works with no permission and no password.

If you plan to rebuild from source, run this once so the grant survives rebuilds:

```bash
bash scripts/setup-signing.sh
```

## What it controls

| Group | Examples |
|---|---|
| Spaces & Mission Control | instant switching (keyboard and trackpad), stop auto-rearranging, group windows by app |
| Animations | window open/close, resize speed, Quick Look, Finder, Dock bounce, minimize effect, Reduce Motion |
| Power | keep the display awake, keep the Mac awake |
| Menu Bar & Clock | auto-hide the menu bar, icon spacing (fit more icons beside the notch), seconds, weekday, date, 24-hour time |
| Dock | auto-hide, hide delay and speed, size, position, recents, indicators, only open apps, scroll to show windows |
| Hot Corners | what each screen corner does: Mission Control, desktop, lock screen, Quick Note, nothing |
| Desktop & Windows | desktop icons, click wallpaper to reveal, Stage Manager, widgets, edge tiling, tile margins, ⌃⌘-drag windows from anywhere, title bar double-click, tabs |
| Finder & Files | extensions, hidden files, path bar, status bar, default view, search scope, `.DS_Store`, save dialogs, empty Trash after 30 days, external disks on the desktop |
| Keyboard & Typing | key repeat, press-and-hold, Tab through all controls, autocorrect, smart quotes and dashes, inline prediction |
| Trackpad & Mouse | tap to click, three-finger drag, natural scrolling, Force Click, tracking speed |
| Screenshots | format, location, shadow, thumbnail, date in the file name |
| System & Apps | scroll bars, sidebar icon size, reopen windows, interface sounds, volume feedback, stop Photos and Time Machine popping up for new devices |

Animations also covers Mission Control speed. Run `knobs list` for the full list with current values.

Each setting says when it takes effect:

- **instant**: right away. Knobs restarts the Dock or Finder for you when that is what it takes.
- **apps opened from now on**: running apps keep the old behaviour until you reopen them.
- **after you log out and back in**: macOS only reads these at login.

## Let an agent drive

`build.sh install` also installs a [Claude Code skill](https://docs.claude.com/en/docs/claude-code/skills) at `~/.claude/skills/knobs`, so Claude Code knows about Knobs in every folder: ask "stop my screen from sleeping" anywhere and it reaches for `knobs` on its own. `knobs skill remove` takes it out; `knobs skill` prints it for other agents. Other agents can read [AGENTS.md](AGENTS.md).

```bash
knobs list --json              # every setting: id, meaning, accepted values, current value, when it applies
knobs describe dock.autohide   # one setting in detail
knobs set dock.autohide on dock.autohideDelay 0
knobs reset dock.autohideDelay # hand it back to the macOS default
knobs set spaces.instant on    # reports whether it is really active, and why not if it is not
knobs status
```

Tell your agent something like:

> Use the `knobs` command to look at my macOS settings (`knobs list --json`). I want everything to feel faster: no animations I don't need, and Spaces that switch instantly. Explain each change before you make it.

The "Agent prompt" button in the window copies a ready-made version. The exit code is 0 when everything applied and 1 when something was refused, with the reason on stderr, so an agent can tell.

## Move to a new Mac

On the old Mac:

```bash
knobs export ~/Desktop/my-mac.knobs.json
```

The file holds every setting you changed, your Space shortcuts, and the config of companion tools ([Paneful](https://github.com/JJ22007/paneful) window shortcuts). It also carries its own instructions, so on the new Mac you can give it to any coding agent and say:

> Set up this Mac from `my-mac.knobs.json`.

Or do it by hand:

```bash
git clone https://github.com/JJ22007/knobs.git && cd knobs && bash build.sh install
knobs apply ~/Desktop/my-mac.knobs.json --dry-run   # see what would change
knobs apply ~/Desktop/my-mac.knobs.json
```

`examples/snappy.knobs.json` is a starter profile if you do not have one yet.

## Shortcuts

Instant switching replaces these keys while it is on. They default to the macOS ones.

```bash
knobs shortcut                      # show
knobs shortcut spaceLeft ctrl+left
knobs shortcut space1 ctrl+1        # jump straight to desktop 1 … space9
knobs shortcut space1 none
```

## How it works

- Preference settings are written the same way `defaults write` does, then read back to confirm macOS accepted them.
- Instant switching posts a synthetic high-velocity trackpad swipe, which makes the Dock finish the transition at once. This is the technique from [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) by jurplel (MIT), vendored in `Vendor/ISS`.
- Keep-awake holds a power assertion, the same mechanism as `caffeinate`.
- Live features need the app running. Turn on "Open Knobs at login" so they come back after a restart.

Files: `~/.config/knobs/config.json` (live features and shortcuts), `~/.config/knobs/status.json` (what is active right now).

## Add your own setting

One entry in `Sources/Catalog.swift` and the window, the command, export and import all pick it up. `AGENTS.md` has the details, written so a coding agent can do it for you.

## License

MIT. Includes InstantSpaceSwitcher's gesture code, also MIT. Icons are from [Lucide](https://github.com/lucide-icons/lucide) (ISC), bundled as SVG in `Resources/icons`.
