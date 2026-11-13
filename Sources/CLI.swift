// The `knobs` command, so scripts and AI agents can read, explain and change settings.
//
// Preference-backed settings are read and written right here, with no app needed.
// Live settings are written to the config file; the Knobs app (started in the
// background if necessary) picks the change up at once and reports back through
// ~/.config/knobs/status.json.

import AppKit

enum CLI {
    static let commands: Set<String> = ["list", "get", "describe", "set", "reset", "export", "apply", "shortcut", "status", "open", "skill", "presets", "scene", "undo", "verify", "mcp", "help", "--help", "-h"]

    private static let usageEN = """
    knobs: read and change macOS settings from scripts and agents.

      knobs list [--json] [--changed] [category]   every setting with its current value
      knobs describe <id> [--json]                 what one setting does, its values, when it takes effect
      knobs get <id> [--json]                      print the current value
      knobs set <id> <value> [<id> <value> ...] [--dry-run] [--json]
                                                   change settings (on/off, a number, or a choice)
      knobs reset <id> [<id> ...] [--dry-run] [--json]
                                                   hand settings back to the macOS default
      knobs shortcut [<name> <combo|none>]         show or change the Space shortcuts (e.g. spaceLeft ctrl+left)
      knobs export [file]                          write all settings and shortcuts as one profile
      knobs apply <file|https-url|preset> [--dry-run] [--json]
                                                   apply a profile; --dry-run only lists the changes
      knobs presets                                ready-made profiles you can apply by name
      knobs scene [<name>] [--dry-run] [--json]    list scenes, or switch to one (settings, Overbright brightness, Paneful windows)
      knobs undo [--list] [--json]                 undo the last change (set, reset, apply or the window)
      knobs status [--json]                        is the app running, and are the live features active
      knobs verify [--json]                        check every written key on this Mac against the catalog (read-only)
      knobs open                                   open the Knobs window
      knobs skill [install|remove]                 teach Claude Code about knobs in every folder (a user-level skill)
      knobs mcp [--allow-write]                    run as an MCP server on stdin/stdout (read-only unless --allow-write)

    Categories: \(Category.allCases.map { $0.rawValue }.joined(separator: ", ")).
    Every change saves a snapshot first; `knobs undo` steps back one change at a time.
    Exit code 0 means everything was applied; 1 means something was refused (the reason is on stderr).
    With --json the result goes to stdout as one JSON object, errors included.
    """

    private static let usageZH = """
    knobs:让脚本和 agent 读取、修改 macOS 设置。

      knobs list [--json] [--changed] [分组]      列出所有设置和当前值
      knobs describe <id> [--json]                 某一项是做什么的、可以取哪些值、何时生效
      knobs get <id> [--json]                      输出当前值
      knobs set <id> <值> [<id> <值> ...] [--dry-run] [--json]
                                                   修改设置(on/off、数字或选项)
      knobs reset <id> [<id> ...] [--dry-run] [--json]
                                                   恢复为 macOS 默认
      knobs shortcut [<名称> <组合键|none>]        查看或修改切换桌面的快捷键(例如 spaceLeft ctrl+left)
      knobs export [文件]                          把所有设置和快捷键导出成一个配置文件
      knobs apply <文件|https 链接|预设名> [--dry-run] [--json]
                                                   应用配置文件;--dry-run 只列出会改什么
      knobs presets                                列出可以直接按名字应用的现成配置
      knobs scene [<名称>] [--dry-run] [--json]     列出场景,或切换到某个场景(设置、Overbright 亮度、Paneful 窗口)
      knobs undo [--list] [--json]                 撤销上一次修改(set、reset、apply 或窗口里的改动)
      knobs status [--json]                        应用是否在运行,实时功能是否生效
      knobs verify [--json]                        在这台 Mac 上核对每个已写入的键是否符合目录(只读)
      knobs open                                   打开 Knobs 窗口
      knobs skill [install|remove]                 让 Claude Code 在任何文件夹都认识 knobs(用户级 skill)
      knobs mcp [--allow-write]                    作为 MCP server 运行(stdin/stdout;不加 --allow-write 时只读)

    分组:\(Category.allCases.map { $0.rawValue }.joined(separator: ", "))。
    值一律用英文书写:on / off、数字,或 `knobs describe` 里列出的选项。
    每次修改前都会先存快照;`knobs undo` 一次撤回一步。
    退出码 0 表示全部生效;1 表示有项目被拒绝(原因输出到 stderr)。
    加 --json 时结果作为一个 JSON 对象输出到 stdout,错误也在里面。
    """

    static var usage: String { L(usageEN, usageZH) }

    static func run(_ args: [String]) -> Int32 {
        var rest = Array(args.dropFirst())
        func flag(_ name: String) -> Bool {
            guard let i = rest.firstIndex(of: name) else { return false }
            rest.remove(at: i)
            return true
        }
        let json = flag("--json")
        let dryRun = flag("--dry-run")
        switch args[0] {
        case "list": return list(json: json, changedOnly: flag("--changed"), category: rest.first)
        case "describe": return json ? eachJSON(rest) { record($0, live: liveStates()) } : each(rest) { print(describe($0)) }
        case "get": return json ? eachJSON(rest) { ["id": $0.id, "value": Changes.shownValue($0, Engine.current($0)), "customized": Engine.current($0) != nil] } : each(rest) { print(shown($0)) }
        case "set": return set(rest, dryRun: dryRun, json: json)
        case "reset": return reset(rest, dryRun: dryRun, json: json)
        case "shortcut": return shortcut(rest)
        case "export": return export(rest.first)
        case "apply": return apply(dryRun: dryRun, path: rest.first, json: json)
        case "status": return status(json: json)
        case "open": return launchApp(background: false) ? 0 : 1
        case "skill": return skill(rest.first ?? "print")
        case "presets": return presets()
        case "scene":
            guard let name = rest.first else { return scenes() }
            return apply(dryRun: dryRun, path: name, json: json)
        case "undo": return undo(list: flag("--list"), json: json)
        case "verify": return verify(json: json)
        case "mcp": return MCPServer(allowWrite: flag("--allow-write")).run()
        default: print(usage); return 0
        }
    }

    // MARK: Agent skill

    /// Claude Code loads skills from ~/.claude/skills in every folder and picks one by its
    /// description, so an agent asked "stop my screen from sleeping" finds knobs without being told.
    static let skillPath = expandTilde("~/.claude/skills/knobs/SKILL.md")

    static var skillText: String {
        """
        ---
        name: knobs
        description: Read, explain and change macOS settings on this Mac with the `knobs` command, and export or apply a whole setup. Use whenever the user wants to change how their Mac looks or behaves (animations, Spaces, keep the display awake, Dock, menu bar and clock, hot corners, Finder, keyboard and trackpad, screenshots, sounds), asks what a setting does, or wants to move their setup to a new Mac.
        ---

        # knobs

        `~/.local/bin/knobs` (just `knobs` if ~/.local/bin is on PATH) changes macOS settings safely: every setting has an id, a plain description, its macOS default, and an honest note on when a change takes effect. No sudo, ever.

        1. Find the setting: `knobs list --json` (all \(catalog.count)), or `knobs list <category>` for one of: \(Category.allCases.map { $0.rawValue }.joined(separator: ", ")).
        2. Change only what the user asked for: `knobs set <id> <value> [<id> <value> ...] --json`. Values are `on`/`off`, a number, or one of the `options` values. Add `--dry-run` to preview. A batch is all or nothing: if one value is refused, nothing is written. Exit code 1 means something was refused; with `--json` the reasons are in `errors`.
        3. Each change reports `before`, `after`, `verified` (the value read back from macOS) and `takesEffect` (`instant`, `newWindows` = apps opened from now on, `relogin` = after logging out and back in). Tell the user what changed and anything that is not instant.
        4. Every change saves a snapshot first. `knobs undo` steps back one change (`knobs undo --list` shows the history); `knobs reset <id>` hands one setting back to the macOS default.

        For MCP clients: `knobs mcp` is a read-only MCP server; `knobs mcp --allow-write` also allows changes.

        Whole setup: `knobs export <file>` saves everything (plus the Paneful window manager config); on another Mac, `knobs apply <file> --dry-run` shows the changes and `knobs apply <file>` makes them.

        The one thing you cannot do: grant the Accessibility permission that instant Space switching needs. If `knobs set spaces.instant on` says it is waiting, ask the user to switch Knobs on in System Settings > Privacy & Security > Accessibility, then check with `knobs status`.

        Set `KNOBS_LANG=en` for English output. Source and docs: \(Profile.repoURL)
        """
    }

    private static func skill(_ action: String) -> Int32 {
        let fm = FileManager.default
        switch action {
        case "install":
            do {
                try fm.createDirectory(atPath: (skillPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try skillText.write(toFile: skillPath, atomically: true, encoding: .utf8)
                print(L("installed the Claude Code skill: \(skillPath)", "已安装 Claude Code skill:\(skillPath)"))
                return 0
            } catch { return fail(L("cannot write \(skillPath)", "无法写入 \(skillPath)")) }
        case "remove":
            try? fm.removeItem(atPath: (skillPath as NSString).deletingLastPathComponent)
            print(L("removed \(skillPath)", "已删除 \(skillPath)"))
            return 0
        default:
            print(skillText)
            return 0
        }
    }

    private static func fail(_ text: String) -> Int32 {
        FileHandle.standardError.write(Data("\(L("error", "错误")): \(text)\n".utf8))
        return 1
    }

    /// With --json, failures are part of the JSON on stdout, so an agent reads one stream.
    private static func failJSON(_ text: String) -> Int32 {
        print(jsonText(["ok": false, "errors": [text]]))
        return 1
    }

    private static func eachJSON(_ ids: [String], _ body: (Setting) -> [String: Any]) -> Int32 {
        guard !ids.isEmpty else { return failJSON(L("give at least one setting id (see `knobs list`)", "请至少给出一个设置 id(用 `knobs list` 查看)")) }
        var out: [[String: Any]] = []
        for id in ids {
            guard let s = catalogByID[id] else { return failJSON(L("unknown setting \"\(id)\" (see `knobs list`)", "不认识的设置“\(id)”(用 `knobs list` 查看)")) }
            out.append(body(s))
        }
        let result: [String: Any] = out.count == 1 ? out[0] : ["settings": out]
        print(jsonText(result))
        return 0
    }

    private static func each(_ ids: [String], _ body: (Setting) -> Void) -> Int32 {
        guard !ids.isEmpty else { return fail(L("give at least one setting id (see `knobs list`)", "请至少给出一个设置 id(用 `knobs list` 查看)")) }
        for id in ids {
            guard let s = catalogByID[id] else { return fail(L("unknown setting \"\(id)\" (see `knobs list`)", "不认识的设置“\(id)”(用 `knobs list` 查看)")) }
            body(s)
        }
        return 0
    }

    // MARK: Reading

    static func typeText(_ s: Setting) -> String {
        switch s.kind {
        case .toggle: return "on | off"
        case .number(let min, let max, _, let unit, let integer):
            return "\(integer ? "whole number" : "number") \(Value.double(min))–\(Value.double(max))\(unit.isEmpty ? "" : " " + unit)"
        case .choice(let options): return options.map { $0.value }.joined(separator: " | ")
        case .text: return "text"
        }
    }

    static func record(_ s: Setting, live: [String: Any]) -> [String: Any] {
        var r: [String: Any] = [
            "id": s.id, "category": s.category.rawValue, "title": s.title, "description": s.detail,
            "accepts": typeText(s), "takesEffect": s.timing.rawValue, "takesEffectText": s.timing.label, "backedBy": s.keyDescription,
            "customized": Engine.current(s) != nil,
        ]
        if case .live = s.backing { r["customized"] = Engine.current(s) == .bool(true) }
        if let v = Engine.effective(s) { r["value"] = v.any }
        if let label = choiceLabel(s, Engine.effective(s)) { r["valueLabel"] = label }
        if let d = s.systemDefault { r["macOSDefault"] = d.any }
        if case .choice(let options) = s.kind { r["options"] = options.map { ["value": $0.value, "label": $0.label] } }
        if let state = live[s.id] as? [String: Any] {
            r["active"] = state["active"]
            if let note = state["note"] as? String, !note.isEmpty { r["note"] = note }
        }
        return r
    }

    /// The label of a choice value ("0" → "When space allows"), so nobody has to guess what a code means.
    static func choiceLabel(_ s: Setting, _ v: Value?) -> String? {
        guard case .choice(let options) = s.kind, let text = v?.asString else { return nil }
        return options.first { $0.value == text }?.label
    }

    /// The effective value as people read it: "on", "0.2", or "0 (When space allows)".
    static func shown(_ s: Setting, fallback: String = "default") -> String {
        guard let v = Engine.effective(s) else { return fallback }
        return choiceLabel(s, v).map { "\(v) (\($0))" } ?? "\(v)"
    }

    static func liveStates() -> [String: Any] {
        guard appIsRunning(), let data = FileManager.default.contents(atPath: ConfigStore.statusPath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj["live"] as? [String: Any] ?? [:]
    }

    private static func list(json: Bool, changedOnly: Bool, category: String?) -> Int32 {
        if let category, Category(rawValue: category) == nil { return fail(L("unknown category \"\(category)\"", "不认识的分组“\(category)”")) }
        let live = liveStates()
        let records = catalog.filter { category == nil || $0.category.rawValue == category }
            .map { record($0, live: live) }
            .filter { !changedOnly || $0["customized"] as? Bool == true }
        if json {
            let data = (try? JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
            print(String(decoding: data, as: UTF8.self))
            return 0
        }
        var lastCategory = ""
        for r in records {
            let c = r["category"] as? String ?? ""
            if c != lastCategory { print("\n\(Category(rawValue: c)?.title ?? c)"); lastCategory = c }
            let value = Value(any: r["value"]).map { "\($0)" } ?? "default"
            let mark = r["customized"] as? Bool == true ? "*" : " "
            let id = (r["id"] as? String ?? "").padding(toLength: 26, withPad: " ", startingAt: 0)
            let label = (r["valueLabel"] as? String).map { "  (\($0))" } ?? ""
            print(" \(mark) \(id) \(value.padding(toLength: 10, withPad: " ", startingAt: 0)) \(r["title"] as? String ?? "")\(label)")
        }
        print(L("\n * = set by you. `knobs describe <id>` explains a setting.", "\n * = 你改过的。用 `knobs describe <id>` 查看某一项的说明。"))
        return 0
    }

    static func describe(_ s: Setting) -> String {
        var lines = ["\(s.id): \(s.title)", "  \(s.detail)",
                     "  \(L("value now:   ", "当前值:  ")) \(shown(s, fallback: L("macOS default", "macOS 默认")))\(Engine.current(s) == nil ? L(" (never changed)", "(从未改过)") : "")",
                     "  \(L("accepts:     ", "可接受:  ")) \(typeText(s))"]
        if let d = s.systemDefault { lines.append("  \(L("macOS default:", "系统默认:")) \(d)") }
        lines.append("  \(L("takes effect:", "生效时机:")) \(s.timing.label)")
        lines.append("  \(L("backed by:   ", "对应键:  ")) \(s.keyDescription)")
        return lines.joined(separator: "\n")
    }

    // MARK: Writing

    private static func set(_ args: [String], dryRun: Bool, json: Bool) -> Int32 {
        guard !args.isEmpty, args.count % 2 == 0 else {
            let usage = L("usage: knobs set <id> <value> [<id> <value> ...] [--dry-run] [--json]", "用法:knobs set <id> <值> [<id> <值> ...] [--dry-run] [--json]")
            return json ? failJSON(usage) : fail(usage)
        }
        let requests = stride(from: 0, to: args.count, by: 2).map { Changes.Request(id: args[$0], value: .string(args[$0 + 1])) }
        return write(requests, dryRun: dryRun, json: json, reason: "knobs set " + args.joined(separator: " "))
    }

    private static func reset(_ ids: [String], dryRun: Bool, json: Bool) -> Int32 {
        guard !ids.isEmpty else {
            let usage = L("give at least one setting id (see `knobs list`)", "请至少给出一个设置 id(用 `knobs list` 查看)")
            return json ? failJSON(usage) : fail(usage)
        }
        return write(ids.map { Changes.Request(id: $0, value: nil) }, dryRun: dryRun, json: json, reason: "knobs reset " + ids.joined(separator: " "))
    }

    /// set and reset: one snapshot, then write, read back and report.
    private static func write(_ requests: [Changes.Request], dryRun: Bool, json: Bool, reason: String) -> Int32 {
        var out = Changes.run(requests, dryRun: dryRun, reason: reason)
        if !dryRun { Changes.confirmLive(&out) }
        if json {
            print(jsonText(out.json))
            return out.ok ? 0 : 1
        }
        for item in out.items {
            guard let id = item["id"] as? String, let s = catalogByID[id], item["error"] == nil else { continue }
            let after = Value(any: item["after"]).map { v in choiceLabel(s, v).map { "\(v) (\($0))" } ?? "\(v)" } ?? L("macOS default", "macOS 默认")
            var line = "\(id) = \(after)"
            if dryRun { line = L("would set ", "将会设为 ") + line + ((item["changed"] as? Bool) == false ? L("  (already so)", "(本来就是)") : "") }
            else if item["reset"] != nil { line += "  " + L("(back to the macOS default)", "(已恢复为 macOS 默认)") }
            else if case .live = s.backing { line += "  (\(item["verified"] as? Bool == true ? L(item["active"] as? Bool == true ? "active now" : "stopped", item["active"] as? Bool == true ? "已生效" : "已停止") : L("not confirmed", "未确认")))" }
            else if s.timing != .instant { line += "  (\(s.timing.label))" }
            print(line)
        }
        out.errors.forEach { _ = fail($0) }
        if out.snapshot != nil { print(L("Changed your mind? `knobs undo` puts it back.", "后悔了?运行 `knobs undo` 即可撤回。")) }
        return out.ok ? 0 : 1
    }

    private static func shortcut(_ args: [String]) -> Int32 {
        if args.count == 2 {
            guard Config.shortcutNames.contains(args[0]) else { return fail(L("unknown shortcut \"\(args[0])\"; names: \(Config.shortcutNames.joined(separator: ", "))", "不认识的快捷键“\(args[0])”;可用名称:\(Config.shortcutNames.joined(separator: ", "))")) }
            let combo = args[1] == "none" ? "" : args[1]
            guard combo.isEmpty || KeyCombo.parse(combo) != nil else { return fail(L("cannot read \"\(combo)\"; write it like ctrl+left or ctrl+alt+1", "无法识别“\(combo)”;请写成 ctrl+left 或 ctrl+alt+1 这样")) }
            ConfigStore.update { $0.shortcuts[args[0]] = combo }
        } else if !args.isEmpty {
            return fail(L("usage: knobs shortcut [<name> <combo|none>]", "用法:knobs shortcut [<名称> <组合键|none>]"))
        }
        let shortcuts = ConfigStore.load().shortcuts
        for name in Config.shortcutNames {
            let combo = shortcuts[name] ?? ""
            print("\(name.padding(toLength: 11, withPad: " ", startingAt: 0)) \(combo.isEmpty ? "none" : combo)")
        }
        print(L("These keys switch Spaces without animation while spaces.instant is on.", "spaces.instant 打开时,这些按键会不带动画地切换桌面空间。"))
        return 0
    }

    // MARK: Profiles

    private static func export(_ path: String?) -> Int32 {
        let text = Profile.exportText()
        guard let path else { print(text, terminator: ""); return 0 }
        do { try text.write(toFile: expandTilde(path), atomically: true, encoding: .utf8) }
        catch { return fail(L("cannot write \(path)", "无法写入 \(path)")) }
        print(L("exported to \(path)", "已导出到 \(path)"))
        return 0
    }

    private static func apply(dryRun: Bool, path: String?, json: Bool) -> Int32 {
        let complain: (String) -> Int32 = json ? failJSON : fail
        guard let path else { return complain(L("usage: knobs apply <file|https-url|preset> [--dry-run] [--json]", "用法:knobs apply <文件|https 链接|预设名> [--dry-run] [--json]")) }
        let text: String
        switch loadProfile(path) {
        case .success(let t): text = t
        case .failure(let e): return complain(e.description)
        }
        if json {
            do {
                let report = try Profile.apply(text: text, dryRun: dryRun, reason: "knobs apply \(tildePath(path))")
                if !dryRun { notifyApp() }
                print(jsonText(report.json(dryRun: dryRun)))
                return report.problems.isEmpty ? 0 : 1
            } catch { return failJSON("\(error)") }
        }
        do {
            let report = try Profile.apply(text: text, dryRun: dryRun, reason: "knobs apply \(tildePath(path))")
            report.changed.forEach { print(L("\(dryRun ? "would change" : "changed") \($0)", "\(dryRun ? "将会更改" : "已更改") \($0)")) }
            print(L("\(report.changed.count) \(dryRun ? "to change" : "changed"), \(report.unchanged) already matched.", "\(dryRun ? "将更改" : "已更改") \(report.changed.count) 项,\(report.unchanged) 项本来就一致。"))
            report.skipped.forEach { print(L("skipped \($0)", "已跳过 \($0)")) }
            report.problems.forEach { _ = fail($0) }
            if !dryRun { notifyApp() }
            if !dryRun, !report.changed.isEmpty { print(L("Changed your mind? `knobs undo` puts everything back.", "后悔了?运行 `knobs undo` 即可全部恢复。")) }
            let liveIDs = dryRun ? [] : catalog.filter { if case .live = $0.backing { return Engine.current($0) == .bool(true) }; return false }.map { $0.id }
            return max(report.problems.isEmpty ? 0 : 1, printLive(liveIDs))
        } catch { return fail("\(error)") }
    }

    // MARK: Profiles from anywhere

    /// Profiles bundled with the app, by name (Contents/Resources/presets/<name>.knobs.json).
    static var presetDirectory: URL? {
        // Resolve the ~/.local/bin/knobs link first: Bundle.main would otherwise point at ~/.local/bin.
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/presets")
    }

    /// Scenes bundled with the app: profiles that also drive companion tools such as Overbright.
    static var sceneDirectory: URL? { presetDirectory?.deletingLastPathComponent().appendingPathComponent("scenes") }

    static func sceneNames() -> [String] {
        guard let dir = sceneDirectory, let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files.filter { $0.hasSuffix(".knobs.json") }.map { String($0.dropLast(".knobs.json".count)) }.sorted()
    }

    static func presetNames() -> [String] {
        guard let dir = presetDirectory, let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files.filter { $0.hasSuffix(".knobs.json") }.map { String($0.dropLast(".knobs.json".count)) }.sorted()
    }

    /// A file path, an https link (a gist, a raw GitHub file) or the name of a bundled preset.
    static func loadProfile(_ source: String) -> Result<String, KnobsError> {
        if source.hasPrefix("http://") { return .failure(KnobsError(L("use an https:// link", "请使用 https:// 链接"))) }
        if source.hasPrefix("https://"), let url = URL(string: source) {
            var result: Result<String, KnobsError> = .failure(KnobsError(L("could not download \(source)", "无法下载 \(source)")))
            let done = DispatchSemaphore(value: 0)
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("knobs", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: request) { data, response, _ in
                if let data, (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000,
                   let text = String(data: data, encoding: .utf8) { result = .success(text) }
                done.signal()
            }.resume()
            done.wait()
            return result
        }
        let path = expandTilde(source)
        if FileManager.default.fileExists(atPath: path), let text = try? String(contentsOfFile: path, encoding: .utf8) { return .success(text) }
        for dir in [presetDirectory, sceneDirectory].compactMap({ $0 }) {
            if let text = try? String(contentsOf: dir.appendingPathComponent("\(source).knobs.json"), encoding: .utf8) { return .success(text) }
        }
        return .failure(KnobsError(L("no file, link or preset called \"\(source)\". Presets: \(presetNames().joined(separator: ", "))",
                                     "找不到名为“\(source)”的文件、链接或预设。可用预设:\(presetNames().joined(separator: ", "))")))
    }

    private static func undo(list: Bool, json: Bool) -> Int32 {
        let all = Profile.backups()
        if list {
            if json {
                print(jsonText(["snapshots": all.map { ["path": tildePath($0), "before": Profile.reason(ofSnapshot: $0)] }]))
                return 0
            }
            if all.isEmpty { print(L("No snapshots yet. One is saved before every change.", "还没有快照。每次修改前都会自动存一份。")) }
            for path in all {
                print("\((path as NSString).lastPathComponent)  \(L("before", "之前:")) \(Profile.reason(ofSnapshot: path))")
            }
            return 0
        }
        let result = Changes.undo()
        if json {
            print(jsonText(result.json))
            return result.error == nil && result.report.problems.isEmpty ? 0 : 1
        }
        if let error = result.error { return fail(error) }
        result.report.changed.forEach { print(L("restored \($0)", "已恢复 \($0)")) }
        print(L("Undid \"\(result.reason)\": \(result.report.changed.count) restored. \(Profile.backups().count) older snapshots left.",
                "已撤销“\(result.reason)”:恢复了 \(result.report.changed.count) 项。还剩 \(Profile.backups().count) 个更早的快照。"))
        result.report.problems.forEach { _ = fail($0) }
        return result.report.problems.isEmpty ? 0 : 1
    }

    private static func verify(json: Bool) -> Int32 {
        let r = Verify.run()
        if json { print(jsonText(r)); return r["ok"] as? Bool == true ? 0 : 1 }
        let counts = r["counts"] as? [String: Int] ?? [:]
        for row in r["settings"] as? [[String: Any]] ?? [] where row["result"] as? String == "mismatch" {
            print("\(row["id"] ?? "")  \(row["backedBy"] ?? "")  \(row["problem"] ?? "")")
        }
        print(L("macOS \(r["macOS"] ?? ""): \(counts["ok"] ?? 0) written keys match the catalog, \(counts["mismatch"] ?? 0) do not, \(counts["unset"] ?? 0) are unset (macOS decides), \(counts["live"] ?? 0) are provided by the app.",
                "macOS \(r["macOS"] ?? ""):\(counts["ok"] ?? 0) 个已写入的键符合目录,\(counts["mismatch"] ?? 0) 个不符合,\(counts["unset"] ?? 0) 个没写过(由 macOS 决定),\(counts["live"] ?? 0) 个由应用提供。"))
        return r["ok"] as? Bool == true ? 0 : 1
    }

    private static func scenes() -> Int32 {
        for name in sceneNames() {
            guard case .success(let text) = loadProfile(name),
                  let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { continue }
            let about = (obj[prefersChinese ? "about.zh" : "about"] as? String) ?? (obj["about"] as? String) ?? ""
            print("\(name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(about)")
        }
        print(L("\nPreview with `knobs scene <name> --dry-run`, switch with `knobs scene <name>`, and go back with `knobs undo`.\(Overbright.installed ? "" : " Overbright is not installed, so brightness is skipped.")\(Paneful.installed ? "" : " Paneful is not installed, so window layouts are skipped.")",
                "\n用 `knobs scene <名称> --dry-run` 预览,`knobs scene <名称>` 切换,`knobs undo` 还原。\(Overbright.installed ? "" : "没有安装 Overbright,亮度部分会跳过。")\(Paneful.installed ? "" : "没有安装 Paneful,窗口布局会跳过。")"))
        return 0
    }

    private static func presets() -> Int32 {
        for name in presetNames() {
            guard case .success(let text) = loadProfile(name),
                  let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { continue }
            let count = (obj["settings"] as? [String: Any])?.count ?? 0
            let about = (obj[prefersChinese ? "about.zh" : "about"] as? String) ?? (obj["about"] as? String) ?? ""
            print("\(name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(L("\(count) settings", "\(count) 项"))  \(about)")
        }
        print(L("\nPreview with `knobs apply <name> --dry-run`, apply with `knobs apply <name>`.", "\n用 `knobs apply <名称> --dry-run` 预览,用 `knobs apply <名称>` 应用。"))
        return 0
    }

    // MARK: Talking to the app

    /// Lets an open Knobs window redraw at once after a change made from the command line.
    static func notifyApp() {
        DistributedNotificationCenter.default().postNotificationName(ConfigStore.changed, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func appIsRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.knobs").isEmpty
    }

    private static func appPath() -> String? {
        let real = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
        if let range = real.range(of: ".app/") { return String(real[..<range.lowerBound]) + ".app" }
        let installed = expandTilde("~/Applications/Knobs.app")
        return FileManager.default.fileExists(atPath: installed) ? installed : nil
    }

    private static func launchApp(background: Bool) -> Bool {
        guard let path = appPath() else { _ = fail(L("Knobs.app is not installed; run `bash build.sh install` in the repository", "还没有安装 Knobs.app;请在仓库目录运行 `bash build.sh install`")); return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = background ? ["-g", "-a", path, "--args", "--background"] : ["-a", path]
        // Never write to stdout here: in `knobs mcp` stdout carries the protocol.
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private static func statusDate() -> Date {
        (try? FileManager.default.attributesOfItem(atPath: ConfigStore.statusPath)[.modificationDate] as? Date) ?? .distantPast
    }

    /// Waits for the app, then prints whether each live feature really is in the state asked for.
    private static func printLive(_ ids: [String]) -> Int32 {
        guard !ids.isEmpty else { return 0 }
        var out = Changes.Outcome()
        out.liveIDs = ids
        out.items = ids.map { ["id": $0] }
        Changes.confirmLive(&out)
        for item in out.items where item["verified"] as? Bool == true {
            let active = item["active"] as? Bool == true
            print("\(item["id"] ?? "") = \(active ? "on" : "off")  (\(L(active ? "active now" : "stopped", active ? "已生效" : "已停止")))")
        }
        out.errors.forEach { _ = fail($0) }
        return out.ok ? 0 : 1
    }

    /// After changing live settings: make sure the app is up and wait for it to act.
    /// Returns the live states it reports, or nil if the app could not be started.
    static func waitForLive(_ ids: [String]) -> [String: Any]? {
        guard !ids.isEmpty else { return [:] }
        let asked = Date().addingTimeInterval(-1.5)
        if !appIsRunning(), !launchApp(background: true) { return nil }
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, !(appIsRunning() && statusDate() > asked) { usleep(50_000) }
        usleep(150_000)
        return liveStates()
    }

    static func statusJSON() -> [String: Any] {
        guard appIsRunning() else { return ["appRunning": false, "live": [:]] }
        let data = FileManager.default.contents(atPath: ConfigStore.statusPath) ?? Data()
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        var live: [String: Any] = [:]
        for s in catalog {
            guard case .live = s.backing else { continue }
            let state = (obj["live"] as? [String: Any])?[s.id] as? [String: Any]
            var entry: [String: Any] = ["wanted": Engine.current(s) == .bool(true), "active": state?["active"] as? Bool ?? false]
            if let note = state?["note"] as? String, !note.isEmpty { entry["note"] = note }
            live[s.id] = entry
        }
        return ["appRunning": true, "accessibility": obj["accessibility"] as? Bool ?? false, "live": live,
                "snapshots": Profile.backups().count]
    }

    private static func status(json: Bool) -> Int32 {
        if json { print(jsonText(statusJSON())); return 0 }
        guard appIsRunning() else { print(L("Knobs app: not running (live features are off until it starts; `knobs open`)", "Knobs 应用:未运行(启动前实时功能不生效;可运行 `knobs open`)")); return 0 }
        let data = FileManager.default.contents(atPath: ConfigStore.statusPath) ?? Data()
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        print(L("Knobs app: running", "Knobs 应用:运行中"))
        print(L("Accessibility permission: \(obj["accessibility"] as? Bool == true ? "granted" : "not granted (needed only for instant Space switching)")", "辅助功能权限:\(obj["accessibility"] as? Bool == true ? "已授予" : "未授予(只有无动画切换桌面需要)")"))
        let live = obj["live"] as? [String: Any] ?? [:]
        for s in catalog {
            guard case .live = s.backing, let state = live[s.id] as? [String: Any] else { continue }
            let note = state["note"] as? String ?? ""
            print("\(s.id.padding(toLength: 22, withPad: " ", startingAt: 0)) \(L("wanted", "期望")) \(Engine.current(s) == .bool(true) ? "on " : "off")  \(state["active"] as? Bool == true ? L("active", "已生效") : L("inactive", "未生效"))\(note.isEmpty ? "" : "  — " + note)")
        }
        return 0
    }
}
