# AGENTS.md

Instructions for AI agents. There are two kinds of work here: using Knobs on someone's Mac, and changing Knobs itself.

## Using Knobs for a user

The command is `~/.local/bin/knobs` (a link into `~/Applications/Knobs.app`). If it is missing, run `bash build.sh install` in this repository.

1. Run `knobs list --json`. Each entry has `id`, `title`, `description`, `accepts`, `value`, `macOSDefault`, `takesEffect` and `customized`; choices also carry `options` and a readable `valueLabel` (hot corner `14` is "Quick Note").
2. Explain what you intend to change in the user's words, using `title` and `description`. Only change what they asked for.
3. `knobs set <id> <value> [<id> <value> ...]`. Exit code 1 means something was refused; the reason is on stderr. Do not report success without checking it.
4. Tell the user about `takesEffect` when it is not instant (reopen the app, or log out and back in).
5. `knobs reset <id>` undoes a change by handing the setting back to macOS.

Output follows the system language. Set `KNOBS_LANG=en` (or `zh`) for a fixed language. Values are always written in English (`on`, `off`, numbers, option names). A Chinese version of this file is `AGENTS.zh-CN.md`.

Setting up a Mac from a profile: `knobs apply <file|https-url|preset> --dry-run`, show the user the list, then apply without `--dry-run`. `knobs undo` reverts the last apply (a snapshot is saved first). `knobs presets` lists the bundled presets; new ones go in `presets/` and are validated by `build.sh`.

The only thing you cannot do for the user is grant the Accessibility permission, which instant Space switching needs. If `knobs set spaces.instant on` says it is waiting for the permission, ask the user to switch Knobs on in System Settings → Privacy & Security → Accessibility. Knobs notices within a second; confirm with `knobs status`. Never try to grant it yourself, and never use `sudo` for anything in this project.

## Changing Knobs

- Swift, compiled with `swiftc` directly, plus one vendored C library in `Vendor/ISS`. No Xcode project, no Swift Package, no other dependencies. Keep it that way.
- The command line toolchain has no SwiftUI macro plugin: `@State` does not compile. Keep view state in `Model` (`@Published`) as `UI.swift` does.
- Icons are [Lucide](https://github.com/lucide-icons/lucide) SVGs in `Resources/icons`, drawn as single-colour template images by `lucide(name, size)`. To use a new one, add its SVG there; do not introduce multi-colour icons or SF Symbols.
- UI text goes through `L("English", "中文")`.

```bash
bash build.sh            # compile, run the self-test, validate presets/
bash build.sh install    # also install to ~/Applications, link ~/.local/bin/knobs, launch
```

| File | Responsibility |
|---|---|
| `Catalog.swift` | The table of settings. Most changes happen only here |
| `Engine.swift` | Read, validate, write and reset a setting; the config file; export and import of profiles |
| `Live.swift` | Features the running app provides: instant Spaces, keep awake, open at login |
| `Keys.swift` | Shortcut parsing and the key event tap |
| `CLI.swift` | The `knobs` command |
| `App.swift` | Menu bar item, window, and the loop that follows the config file |
| `UI.swift` | The SwiftUI window, drawn from the catalog |
| `main.swift` | Entry point and `--selftest` |

### Add a setting

Add one entry to `catalog` in `Catalog.swift` with the `toggle`, `number` or `choice` helper:

```swift
toggle("dock.autohide", .dock, "Hide the Dock automatically", "自动隐藏程序坞",
       "English description.", "中文说明。",
       "com.apple.dock", "autohide", default: false, restart: ["Dock"]),
```

- `default:` is what macOS does when the key was never written. Get it right, or the window shows the wrong state on a fresh Mac. If you cannot find out, use a `number` without a default.
- `restart:` names the processes that must be restarted for the change to show. `timing:` must be honest: use `.newWindows` or `.relogin` when a restart of Dock/Finder is not enough.
- `inverted: true` when the key means the opposite of the title (`DisableAllAnimations`).
- Verify on a real Mac: `knobs set`, look at the result, `knobs reset`. Do not add keys copied from old dotfiles without checking they still do something on current macOS.

### What you cannot verify yourself

Instant Space switching needs the Accessibility permission, which only the user can grant, and its effect is visual. Say so plainly instead of claiming it was tested end to end. What you can verify: the self-test, `knobs status`, `pmset -g assertions` for keep-awake, and `defaults read` after a `knobs set`.
