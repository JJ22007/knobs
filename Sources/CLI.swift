// The `knobs` command, so scripts and AI agents can read, explain and change settings.
//
// Preference-backed settings are read and written right here, with no app needed.
// Live settings are written to the config file; the Knobs app (started in the
// background if necessary) picks the change up at once and reports back through
// ~/.config/knobs/status.json.

import AppKit

enum CLI {
    static let commands: Set<String> = ["list", "get", "describe", "set", "reset", "export", "apply", "shortcut", "status", "open", "skill", "presets", "help", "--help", "-h"]

    private static let usageEN = """
    knobs: read and change macOS settings from scripts and agents.

      knobs list [--json] [--changed] [category]   every setting with its current value
      knobs describe <id>                          what one setting does, its values, when it takes effect
      knobs get <id>                               print the current value
      knobs set <id> <value> [<id> <value> ...]    change settings (on/off, a number, or a choice)
      knobs reset <id> [<id> ...]                  hand settings back to the macOS default
      knobs shortcut [<name> <combo|none>]         show or change the Space shortcuts (e.g. spaceLeft ctrl+left)
      knobs export [file]                          write all settings and shortcuts as one profile
      knobs apply <file|https-url|preset> [--dry-run]
                                                   apply a profile; --dry-run only lists the changes
      knobs presets                                ready-made profiles you can apply by name
      knobs status                                 is the app running, and are the live features active
      knobs open                                   open the Knobs window
      knobs skill [install|remove]                 teach Claude Code about knobs in every folder (a user-level skill)

    Categories: \(Category.allCases.map { $0.rawValue }.joined(separator: ", ")).
    Exit code 0 means everything was applied; 1 means something was refused (the reason is on stderr).
    """

    private static let usageZH = """
    knobs:让脚本和 agent 读取、修改 macOS 设置。

      knobs list [--json] [--changed] [分组]      列出所有设置和当前值
      knobs describe <id>                          某一项是做什么的、可以取哪些值、何时生效
      knobs get <id>                               输出当前值
      knobs set <id> <值> [<id> <值> ...]          修改设置(on/off、数字或选项)
      knobs reset <id> [<id> ...]                  恢复为 macOS 默认
      knobs shortcut [<名称> <组合键|none>]        查看或修改切换桌面的快捷键(例如 spaceLeft ctrl+left)
      knobs export [文件]                          把所有设置和快捷键导出成一个配置文件
      knobs apply <文件|https 链接|预设名> [--dry-run]
                                                   应用配置文件;--dry-run 只列出会改什么
      knobs presets                                列出可以直接按名字应用的现成配置
      knobs status                                 应用是否在运行,实时功能是否生效
      knobs open                                   打开 Knobs 窗口
      knobs skill [install|remove]                 让 Claude Code 在任何文件夹都认识 knobs(用户级 skill)

    分组:\(Category.allCases.map { $0.rawValue }.joined(separator: ", "))。
    值一律用英文书写:on / off、数字,或 `knobs describe` 里列出的选项。
    退出码 0 表示全部生效;1 表示有项目被拒绝(原因输出到 stderr)。
    """

    static var usage: String { L(usageEN, usageZH) }

    static func run(_ args: [String]) -> Int32 {
        var rest = Array(args.dropFirst())
        func flag(_ name: String) -> Bool {
            guard let i = rest.firstIndex(of: name) else { return false }
            rest.remove(at: i)
            return true
        }
        switch args[0] {
        case "list": return list(json: flag("--json"), changedOnly: flag("--changed"), category: rest.first)
        case "describe": return each(rest) { print(describe($0)) }
        case "get": return each(rest) { print(shown($0)) }
        case "set": return set(rest)
        case "reset": return reset(rest)
        case "shortcut": return shortcut(rest)
        case "export": return export(rest.first)
        case "apply": return apply(dryRun: flag("--dry-run"), path: rest.first)
        case "status": return status()
        case "open": return launchApp(background: false) ? 0 : 1
        case "skill": return skill(rest.first ?? "print")
        case "presets": return presets()
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

        `\(expandTilde("~/.local/bin/knobs"))` changes macOS settings safely: every setting has an id, a plain description, its macOS default, and an honest note on when a change takes effect. No sudo, ever.

        1. Find the setting: `knobs list --json` (all \(catalog.count)), or `knobs list <category>` for one of: \(Category.allCases.map { $0.rawValue }.joined(separator: ", ")).
        2. Change only what the user asked for: `knobs set <id> <value> [<id> <value> ...]`. Values are `on`/`off`, a number, or one of the `options` values. Exit code 1 means something was refused; the reason is on stderr.
        3. Tell the user what changed and when it takes effect (`takesEffect`: instant, apps opened from now on, or after logging out).
        4. Undo with `knobs reset <id>`.

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

    private static func each(_ ids: [String], _ body: (Setting) -> Void) -> Int32 {
        guard !ids.isEmpty else { return fail(L("give at least one setting id (see `knobs list`)", "请至少给出一个设置 id(用 `knobs list` 查看)")) }
        for id in ids {
            guard let s = catalogByID[id] else { return fail(L("unknown setting \"\(id)\" (see `knobs list`)", "不认识的设置“\(id)”(用 `knobs list` 查看)")) }
            body(s)
        }
        return 0
    }

    // MARK: Reading

    private static func typeText(_ s: Setting) -> String {
        switch s.kind {
        case .toggle: return "on | off"
        case .number(let min, let max, _, let unit, let integer):
            return "\(integer ? "whole number" : "number") \(Value.double(min))–\(Value.double(max))\(unit.isEmpty ? "" : " " + unit)"
        case .choice(let options): return options.map { $0.value }.joined(separator: " | ")
        case .text: return "text"
        }
    }

    private static func record(_ s: Setting, live: [String: Any]) -> [String: Any] {
        var r: [String: Any] = [
            "id": s.id, "category": s.category.rawValue, "title": s.title, "description": s.detail,
            "accepts": typeText(s), "takesEffect": s.timing.label, "backedBy": s.keyDescription,
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

    private static func liveStates() -> [String: Any] {
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

    private static func describe(_ s: Setting) -> String {
        var lines = ["\(s.id): \(s.title)", "  \(s.detail)",
                     "  \(L("value now:   ", "当前值:  ")) \(shown(s, fallback: L("macOS default", "macOS 默认")))\(Engine.current(s) == nil ? L(" (never changed)", "(从未改过)") : "")",
                     "  \(L("accepts:     ", "可接受:  ")) \(typeText(s))"]
        if let d = s.systemDefault { lines.append("  \(L("macOS default:", "系统默认:")) \(d)") }
        lines.append("  \(L("takes effect:", "生效时机:")) \(s.timing.label)")
        lines.append("  \(L("backed by:   ", "对应键:  ")) \(s.keyDescription)")
        return lines.joined(separator: "\n")
    }

    // MARK: Writing

    private static func set(_ args: [String]) -> Int32 {
        guard !args.isEmpty, args.count % 2 == 0 else { return fail(L("usage: knobs set <id> <value> [<id> <value> ...]", "用法:knobs set <id> <值> [<id> <值> ...]")) }
        var restart = Set<String>()
        var liveIDs: [String] = []
        var code: Int32 = 0
        for i in stride(from: 0, to: args.count, by: 2) {
            guard let s = catalogByID[args[i]] else { code = fail(L("unknown setting \"\(args[i])\" (see `knobs list`)", "不认识的设置“\(args[i])”(用 `knobs list` 查看)")); continue }
            do {
                restart.formUnion(try Engine.set(s, .string(args[i + 1])))
                if case .live = s.backing { liveIDs.append(s.id) }
                else { print("\(s.id) = \(shown(s))\(s.timing == .instant ? "" : "  (\(s.timing.label))")") }
            } catch { code = fail("\(error)") }
        }
        Prefs.restart(restart)
        notifyApp()
        return max(code, reportLive(liveIDs))
    }

    private static func reset(_ ids: [String]) -> Int32 {
        var restart = Set<String>()
        var liveIDs: [String] = []
        let code = each(ids) { s in
            restart.formUnion(Engine.reset(s))
            if case .live = s.backing { liveIDs.append(s.id) }
            else { print("\(s.id) = \(shown(s, fallback: L("macOS default", "macOS 默认")))  \(L("(back to the macOS default)", "(已恢复为 macOS 默认)"))") }
        }
        Prefs.restart(restart)
        notifyApp()
        return max(code, reportLive(liveIDs))
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

    private static func apply(dryRun: Bool, path: String?) -> Int32 {
        guard let path else { return fail(L("usage: knobs apply <file|https-url|preset> [--dry-run]", "用法:knobs apply <文件|https 链接|预设名> [--dry-run]")) }
        let text: String
        switch loadProfile(path) {
        case .success(let t): text = t
        case .failure(let e): return fail(e.description)
        }
        do {
            let report = try Profile.apply(text: text, dryRun: dryRun)
            report.changed.forEach { print(L("\(dryRun ? "would change" : "changed") \($0)", "\(dryRun ? "将会更改" : "已更改") \($0)")) }
            print(L("\(report.changed.count) \(dryRun ? "to change" : "changed"), \(report.unchanged) already matched.", "\(dryRun ? "将更改" : "已更改") \(report.changed.count) 项,\(report.unchanged) 项本来就一致。"))
            report.problems.forEach { _ = fail($0) }
            if !dryRun { notifyApp() }
            let liveIDs = dryRun ? [] : catalog.filter { if case .live = $0.backing { return Engine.current($0) == .bool(true) }; return false }.map { $0.id }
            return max(report.problems.isEmpty ? 0 : 1, reportLive(liveIDs))
        } catch { return fail("\(error)") }
    }

    // MARK: Profiles from anywhere

    /// Profiles bundled with the app, by name (Contents/Resources/presets/<name>.knobs.json).
    static var presetDirectory: URL? {
        // Resolve the ~/.local/bin/knobs link first: Bundle.main would otherwise point at ~/.local/bin.
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/presets")
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
        if let dir = presetDirectory, let text = try? String(contentsOf: dir.appendingPathComponent("\(source).knobs.json"), encoding: .utf8) {
            return .success(text)
        }
        return .failure(KnobsError(L("no file, link or preset called \"\(source)\". Presets: \(presetNames().joined(separator: ", "))",
                                     "找不到名为“\(source)”的文件、链接或预设。可用预设:\(presetNames().joined(separator: ", "))")))
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
    private static func notifyApp() {
        DistributedNotificationCenter.default().postNotificationName(ConfigStore.changed, object: nil, userInfo: nil, deliverImmediately: true)
    }

    private static func appIsRunning() -> Bool {
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
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private static func statusDate() -> Date {
        (try? FileManager.default.attributesOfItem(atPath: ConfigStore.statusPath)[.modificationDate] as? Date) ?? .distantPast
    }

    /// After changing live settings: make sure the app is up, wait for it to act, and say what happened.
    private static func reportLive(_ ids: [String]) -> Int32 {
        guard !ids.isEmpty else { return 0 }
        let asked = Date().addingTimeInterval(-1.5)
        if !appIsRunning(), !launchApp(background: true) { return 1 }
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, !(appIsRunning() && statusDate() > asked) { usleep(50_000) }
        usleep(150_000)
        let live = liveStates()
        var code: Int32 = 0
        for id in ids {
            guard let s = catalogByID[id] else { continue }
            let wanted = Engine.current(s) == .bool(true)
            let state = live[id] as? [String: Any]
            let active = state?["active"] as? Bool ?? false
            let note = state?["note"] as? String ?? ""
            if state == nil { code = fail(L("\(id): the Knobs app did not answer", "\(id):Knobs 应用没有响应")) }
            else if wanted == active { print(L("\(id) = \(wanted ? "on" : "off")  (\(wanted ? "active now" : "stopped"))", "\(id) = \(wanted ? "on" : "off")  (\(wanted ? "已生效" : "已停止"))")) }
            else { code = fail(L("\(id) is set to \(wanted ? "on" : "off") but is \(active ? "still active" : "not active yet")\(note.isEmpty ? "" : ": " + note)", "\(id) 已设为 \(wanted ? "on" : "off"),但\(active ? "仍在生效" : "还没有生效")\(note.isEmpty ? "" : ":" + note)")) }
        }
        return code
    }

    private static func status() -> Int32 {
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
