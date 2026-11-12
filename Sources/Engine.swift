// Reads and writes settings. Shared by the window, the menu bar and the command line.
//
// Preference-backed settings: macOS is the source of truth. Knobs reads the real
// value every time and writes it the same way `defaults write` does.
// Live settings (instant Spaces, keep awake): the config file records what you
// want and the running app makes it so.

import Foundation

struct KnobsError: Error, CustomStringConvertible {
    let description: String
    init(_ text: String) { description = text }
}

// MARK: - Preferences

enum Prefs {
    private static func domain(_ name: String) -> CFString {
        name == "NSGlobalDomain" ? kCFPreferencesAnyApplication : name as CFString
    }

    static func read(_ p: Pref) -> Value? {
        let host = p.currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
        CFPreferencesSynchronize(domain(p.domain), kCFPreferencesCurrentUser, host)
        return Value(any: CFPreferencesCopyValue(p.key as CFString, domain(p.domain), kCFPreferencesCurrentUser, host))
    }

    /// nil deletes the key, which hands the decision back to macOS.
    @discardableResult
    static func write(_ p: Pref, _ value: Value?) -> Bool {
        let host = p.currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
        CFPreferencesSetValue(p.key as CFString, value.map { $0.any as CFPropertyList }, domain(p.domain), kCFPreferencesCurrentUser, host)
        return CFPreferencesSynchronize(domain(p.domain), kCFPreferencesCurrentUser, host)
    }

    /// Dock, Finder and friends only read their preferences at launch. launchd brings them straight back.
    static func restart(_ names: Set<String>) {
        for name in names.sorted() {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            p.arguments = [name]
            p.standardError = FileHandle.nullDevice
            p.standardOutput = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }
}

// MARK: - Config file

struct Config: Equatable {
    var live: [String: Bool] = [:]
    var shortcuts: [String: String] = Config.defaultShortcuts

    static let defaultShortcuts = ["spaceLeft": "ctrl+left", "spaceRight": "ctrl+right"]
    /// spaceLeft, spaceRight, space1 … space9
    static let shortcutNames = ["spaceLeft", "spaceRight"] + (1...9).map { "space\($0)" }

    init() {}

    init(json: [String: Any]) {
        if let l = json["live"] as? [String: Any] {
            for (k, v) in l { if let b = Value(any: v)?.asBool { live[k] = b } }
        }
        if let s = json["shortcuts"] as? [String: Any] {
            for (k, v) in s { if let text = v as? String { shortcuts[k] = text } }
        }
    }

    var json: [String: Any] { ["live": live, "shortcuts": shortcuts] }
}

enum ConfigStore {
    static let dir = expandTilde("~/.config/knobs")
    static let path = dir + "/config.json"
    static let statusPath = dir + "/status.json"
    static let changed = Notification.Name("io.github.knobs.changed")

    static func load() -> Config {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Config() }
        return Config(json: obj)
    }

    static func save(_ config: Config) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: config.json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        // Tell the running app (or the open window) right away instead of waiting for it to notice the file.
        DistributedNotificationCenter.default().postNotificationName(changed, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func update(_ change: (inout Config) -> Void) {
        var c = load()
        change(&c)
        save(c)
    }
}

// MARK: - Engine

enum Engine {
    /// The value as it is right now. nil means the key was never written and macOS decides.
    static func current(_ s: Setting) -> Value? {
        switch s.backing {
        case .prefs(let prefs, _):
            guard let raw = Prefs.read(prefs[0]) else { return nil }
            if case .toggle = s.kind { return raw.asBool.map { .bool(s.inverted ? !$0 : $0) } }
            if s.intChoice, let d = raw.asDouble { return .string(String(Int(d))) }
            if s.id == "screenshots.location", let path = raw.asString {
                return .string((path as NSString).abbreviatingWithTildeInPath)
            }
            // System Settings stores some whole numbers as reals; report one shape per setting.
            if case .number(_, _, _, _, let integer) = s.kind, let d = raw.asDouble {
                return integer ? .int(Int(d.rounded())) : .double(d)
            }
            return raw
        case .live:
            return .bool(ConfigStore.load().live[s.id] ?? false)
        }
    }

    /// What the user actually experiences: the current value, or the macOS default.
    static func effective(_ s: Setting) -> Value? { current(s) ?? s.systemDefault }

    /// Turn loose input ("on", 0.2, "left") into a value this setting accepts.
    static func validate(_ s: Setting, _ input: Value) throws -> Value {
        switch s.kind {
        case .toggle:
            guard let b = input.asBool else { throw KnobsError(L("\(s.id) takes on or off, not \"\(input)\"", "\(s.id) 只接受 on 或 off,不能是“\(input)”")) }
            return .bool(b)
        case .number(let min, let max, _, _, let integer):
            guard let d = input.asDouble else { throw KnobsError(L("\(s.id) takes a number, not \"\(input)\"", "\(s.id) 需要一个数字,不能是“\(input)”")) }
            guard d >= min, d <= max else { throw KnobsError(L("\(s.id) must be between \(Value.double(min)) and \(Value.double(max)), got \(input)", "\(s.id) 必须在 \(Value.double(min)) 到 \(Value.double(max)) 之间,收到的是 \(input)")) }
            return integer ? .int(Int(d.rounded())) : .double(d)
        case .choice(let options):
            guard let text = input.asString, options.contains(where: { $0.value == text }) else {
                throw KnobsError(L("\(s.id) takes one of: \(options.map { $0.value }.joined(separator: ", ")); got \"\(input)\"", "\(s.id) 只能是以下之一:\(options.map { $0.value }.joined(separator: ", "));收到的是“\(input)”"))
            }
            return .string(text)
        case .text:
            guard let text = input.asString else { throw KnobsError(L("\(s.id) takes text", "\(s.id) 需要一段文字")) }
            return .string(text)
        }
    }

    /// Apply one setting. Returns the processes that must be restarted for it to show.
    /// Pass them to `Prefs.restart` once you are done with the whole batch.
    static func set(_ s: Setting, _ input: Value) throws -> Set<String> {
        var value = try validate(s, input)
        switch s.backing {
        case .live:
            let on = value.asBool ?? false
            ConfigStore.update { $0.live[s.id] = on }
            return []
        case .prefs(let prefs, let restart):
            if s.id == "screenshots.location" {
                let text = value.asString ?? ""
                if text.isEmpty { return reset(s) }
                let full = expandTilde(text)
                do { try FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true) }
                catch { throw KnobsError(L("cannot create folder \(full)", "无法创建文件夹 \(full)")) }
                value = .string(full)
            }
            if s.inverted, let b = value.asBool { value = .bool(!b) }
            if s.intChoice, let text = value.asString, let n = Int(text) { value = .int(n) }
            let before = Prefs.read(prefs[0])
            for p in prefs { Prefs.write(p, value) }
            guard Prefs.read(prefs[0]) == value else {
                throw KnobsError(L("macOS did not accept the change to \(s.id) (\(prefs[0].domain) \(prefs[0].key))", "macOS 没有接受对 \(s.id) 的修改(\(prefs[0].domain) \(prefs[0].key))"))
            }
            return before == value ? [] : Set(restart)
        }
    }

    /// Hand the setting back to macOS (delete the key), or switch a live feature off.
    static func reset(_ s: Setting) -> Set<String> {
        switch s.backing {
        case .live:
            ConfigStore.update { $0.live[s.id] = false }
            return []
        case .prefs(let prefs, let restart):
            let before = Prefs.read(prefs[0])
            for p in prefs { Prefs.write(p, nil) }
            return before == nil ? [] : Set(restart)
        }
    }
}

// MARK: - Profiles (export and import)

enum Profile {
    /// Other tools whose config travels with the profile. Only these paths are ever written on import.
    /// Today this is only Paneful, the author's own window tool; a file is exported only when it exists.
    /// To add another tool, add its config path here (README: "Move to a new Mac").
    static let companionFiles = ["~/.config/paneful/config.json"]
    static let repoURL = "https://github.com/JJ22007/knobs"

    static func export() -> [String: Any] {
        var settings: [String: Any] = [:]
        for s in catalog {
            guard let v = Engine.current(s) else { continue }
            if case .live = s.backing, v == .bool(false) { continue }
            settings[s.id] = v.any
        }
        var files: [String: String] = [:]
        for path in companionFiles {
            if let text = try? String(contentsOfFile: expandTilde(path), encoding: .utf8) { files[path] = shortenHome(text) }
        }
        let iso = ISO8601DateFormatter()
        return [
            "knobs": 1,
            "about": "A Knobs profile: one person's macOS settings and shortcuts. "
                + "To set up a Mac from this file (instructions for a person or an AI agent): "
                + "1) git clone \(repoURL) && cd knobs && bash build.sh install   "
                + "2) ~/.local/bin/knobs apply <this file>   "
                + "3) if the output says the Accessibility permission is needed, ask the user to switch Knobs on in "
                + "System Settings > Privacy & Security > Accessibility; nothing else needs a password.   "
                + "Run `knobs apply <this file> --dry-run` first to see what would change.",
            "exportedAt": iso.string(from: Date()),
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "settings": settings,
            "shortcuts": ConfigStore.load().shortcuts,
            "files": files,
        ]
    }

    /// A profile is meant to be shared, so it never carries the account name: paths inside
    /// companion files are written as ~/… and expanded again on the Mac that applies them.
    static func shortenHome(_ text: String) -> String {
        text.replacingOccurrences(of: "\"" + NSHomeDirectory() + "/", with: "\"~/")
    }
    static func expandHome(_ text: String) -> String {
        text.replacingOccurrences(of: "\"~/", with: "\"" + NSHomeDirectory() + "/")
    }

    // MARK: Snapshots, so any change can be undone

    static var backupDirectory: String { expandTilde("~/.config/knobs/backups") }

    /// Everything as it is now, including which settings are untouched, so applying the
    /// snapshot later puts the Mac back exactly (settings a profile turned on get reset).
    static func snapshot(reason: String, extra: [String: Any] = [:]) -> [String: Any] {
        var obj = export()
        for (k, v) in extra { obj[k] = v }
        obj["about"] = "A Knobs snapshot taken automatically before a change. `knobs undo` restores it."
        obj["reason"] = reason
        obj["reset"] = catalog.filter { s in
            if case .live = s.backing { return Engine.current(s) != .bool(true) }
            return Engine.current(s) == nil
        }.map { $0.id }
        return obj
    }

    /// How many snapshots are kept. Every change from the window, the command line or an agent
    /// saves one, so this is the depth of `knobs undo`.
    static let snapshotLimit = 50

    /// Saves a snapshot and keeps the newest `snapshotLimit`. Returns its path.
    @discardableResult
    static func saveSnapshot(reason: String, extra: [String: Any] = [:]) -> String? {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: backupDirectory, withIntermediateDirectories: true)
        // Milliseconds keep two changes in the same second apart and in order.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = f.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let path = backupDirectory + "/\(stamp).knobs.json"
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot(reason: reason, extra: extra), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              // Owner-only: a snapshot can hold window titles from the saved Paneful layout.
              fm.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600]) else { return nil }
        for old in backups().dropFirst(snapshotLimit) { try? fm.removeItem(atPath: old) }
        return path
    }

    /// What a snapshot was taken before ("knobs set dock.autohide on"), for `knobs undo --list`.
    static func reason(ofSnapshot path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return obj["reason"] as? String ?? L("applying a profile", "应用配置文件")
    }

    /// Snapshot paths, newest first.
    static func backups() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: backupDirectory)) ?? []
        return files.filter { $0.hasSuffix(".knobs.json") }.sorted(by: >).map { backupDirectory + "/" + $0 }
    }

    static func exportText() -> String {
        let data = (try? JSONSerialization.data(withJSONObject: export(), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    struct Report {
        var changed: [String] = []
        var unchanged = 0
        var problems: [String] = []
        /// The same changes, structured for --json and MCP: kind, id, before, after.
        var details: [[String: Any]] = []
        var snapshot: String?

        mutating func note(_ kind: String, _ id: String, _ before: Any?, _ after: Any?) {
            details.append(["kind": kind, "id": id, "before": before ?? NSNull(), "after": after ?? NSNull()])
        }

        func json(dryRun: Bool) -> [String: Any] {
            ["ok": problems.isEmpty, "dryRun": dryRun, "changes": details, "unchanged": unchanged,
             "errors": problems, "snapshot": snapshot.map(tildePath) ?? NSNull()]
        }
    }

    /// Apply a profile. With `dryRun` nothing is written and the report says what would change.
    static func apply(text: String, dryRun: Bool, snapshot: Bool = true, reason: String = "knobs apply") throws -> Report {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw KnobsError(L("not a JSON object", "不是有效的 JSON 文件"))
        }
        guard obj["knobs"] != nil, let settings = obj["settings"] as? [String: Any] else {
            throw KnobsError(L("not a Knobs profile (missing \"knobs\" or \"settings\")", "不是 Knobs 配置文件(缺少 knobs 或 settings 字段)"))
        }
        // Before changing anything, remember how things were so `knobs undo` can put them back.
        var report = Report()
        // A scene can also set Overbright's brightness; the snapshot then remembers where it was.
        let brightness = (obj["overbright"] as? [String: Any])?["percent"] as? NSNumber
        // And arrange windows with Paneful ("layout"); a snapshot carries the saved layout ("restore").
        let paneful = obj["paneful"] as? [String: Any]
        let layout = paneful?["layout"] as? [[String: Any]]
        let restoreLayout = paneful?["restore"] as? [[String: Any]]
        if !dryRun, snapshot, let preview = try? apply(text: text, dryRun: true), !preview.changed.isEmpty {
            var extra: [String: Any] = [:]
            if brightness != nil, let now = Overbright.currentPercent() { extra["overbright"] = ["percent": now] }
            if let layout, Paneful.problems(layout).isEmpty, let saved = Paneful.saveLayout() { extra["paneful"] = ["restore": saved] }
            report.snapshot = saveSnapshot(reason: reason, extra: extra)
        }
        var restart = Set<String>()

        // A snapshot lists the settings that were untouched; hand those back to macOS.
        for id in (obj["reset"] as? [String] ?? []).sorted() {
            guard let s = catalogByID[id], settings[id] == nil else { continue }
            let now = Engine.current(s)
            let isOn: Bool = { if case .live = s.backing { return now == .bool(true) }; return now != nil }()
            guard isOn else { continue }
            report.changed.append("\(id): \(now.map { "\($0)" } ?? "") → \(L("macOS default", "macOS 默认"))")
            report.note("setting", id, now?.any, s.systemDefault?.any)
            if !dryRun {
                restart.formUnion(Engine.reset(s))
                report.details[report.details.count - 1]["verified"] = Engine.current(s) == nil || { if case .live = s.backing { return true }; return false }()
            }
        }

        for id in settings.keys.sorted() {
            guard let s = catalogByID[id] else { report.problems.append(L("\(id): unknown setting, skipped", "\(id):不认识的设置,已跳过")); continue }
            guard let raw = Value(any: settings[id]), let wanted = try? Engine.validate(s, raw) else {
                report.problems.append(L("\(id): value \(settings[id] ?? "null") is not valid, skipped", "\(id):值 \(settings[id] ?? "null") 无效,已跳过")); continue
            }
            let now = Engine.current(s)
            // An unset key that already behaves as wanted is left unset.
            if now == wanted || (now == nil && s.systemDefault == wanted) { report.unchanged += 1; continue }
            report.changed.append("\(id): \((now ?? s.systemDefault).map { "\($0)" } ?? L("system default", "系统默认")) → \(wanted)")
            report.note("setting", id, (now ?? s.systemDefault)?.any, wanted.any)
            if dryRun { continue }
            do {
                restart.formUnion(try Engine.set(s, wanted))
                report.details[report.details.count - 1]["verified"] = true   // Engine.set read it back
            } catch {
                report.details[report.details.count - 1]["verified"] = false
                report.problems.append("\(error)")
            }
        }

        if let shortcuts = obj["shortcuts"] as? [String: String] {
            let now = ConfigStore.load().shortcuts
            for name in shortcuts.keys.sorted() where now[name] != shortcuts[name] {
                guard Config.shortcutNames.contains(name) else { report.problems.append(L("shortcut \(name): unknown name, skipped", "快捷键 \(name):不认识的名称,已跳过")); continue }
                let combo = shortcuts[name] ?? ""
                guard combo.isEmpty || KeyCombo.parse(combo) != nil else { report.problems.append(L("shortcut \(name): cannot read \"\(combo)\", skipped", "快捷键 \(name):无法识别“\(combo)”,已跳过")); continue }
                report.changed.append(L("shortcut \(name): \(now[name] ?? "none") → \(combo.isEmpty ? "none" : combo)", "快捷键 \(name):\(now[name] ?? "none") → \(combo.isEmpty ? "none" : combo)"))
                report.note("shortcut", name, now[name] ?? "none", combo.isEmpty ? "none" : combo)
                if !dryRun { ConfigStore.update { $0.shortcuts[name] = combo } }
            }
        }

        if let files = obj["files"] as? [String: String] {
            for path in files.keys.sorted() {
                guard companionFiles.contains(path), let shared = files[path] else {
                    report.problems.append(L("file \(path): not on the list of files a profile may write, skipped", "文件 \(path):不在配置文件允许写入的清单里,已跳过")); continue
                }
                let wanted = expandHome(shared)
                let full = expandTilde(path)
                let existing = try? String(contentsOfFile: full, encoding: .utf8)
                if existing == wanted { report.unchanged += 1; continue }
                report.changed.append(L("file \(path): \(existing == nil ? "created" : "replaced (old copy kept as .bak)")", "文件 \(path):\(existing == nil ? "新建" : "已替换(旧文件保留为 .bak)")"))
                report.note("file", path, existing == nil ? nil : "existing file", "file from the profile")
                if dryRun { continue }
                try? FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                if let existing { try? existing.write(toFile: full + ".bak", atomically: true, encoding: .utf8) }
                do { try wanted.write(toFile: full, atomically: true, encoding: .utf8) }
                catch { report.problems.append(L("file \(path): could not write", "文件 \(path):写入失败")) }
            }
        }

        if !dryRun { Prefs.restart(restart) }

        if let wanted = brightness?.doubleValue {
            if !Overbright.installed {
                report.problems.append(L("overbright: not installed, brightness skipped (https://github.com/JJ22007/overbright)", "overbright:没有安装,已跳过亮度(https://github.com/JJ22007/overbright)"))
            } else if let now = Overbright.currentPercent(), abs(now - wanted) < 0.5 {
                report.unchanged += 1
            } else if dryRun {
                let now = Overbright.currentPercent()
                report.changed.append("overbright: \(now.map { "\(Int($0))%" } ?? "?") → \(Int(wanted))%")
                report.details.append(["kind": "overbright", "id": "overbright.percent", "before": now ?? NSNull(), "after": wanted])
            } else {
                let (entry, ok) = Overbright.set(percent: wanted)
                report.changed.append("overbright: \((entry["before"] as? Double).map { "\(Int($0))%" } ?? "?") → \(Int(wanted))%  (\(entry["readback"] ?? "no answer"))")
                report.details.append(entry)
                if !ok { report.problems.append("overbright: \(entry["error"] ?? "")") }
            }
        }

        if let windows = layout ?? restoreLayout {
            let restoring = layout == nil
            let bad = restoring ? [] : Paneful.problems(windows)
            if !bad.isEmpty {
                report.problems += bad.map { "paneful: " + $0 + L(" (window layout skipped)", "(已跳过窗口布局)") }
            } else if !Paneful.installed {
                report.problems.append(L("paneful: not installed, window layout skipped (https://github.com/JJ22007/paneful)", "paneful:没有安装,已跳过窗口布局(https://github.com/JJ22007/paneful)"))
            } else if dryRun {
                report.changed.append(restoring ? L("paneful: put \(windows.count) window(s) back", "paneful:把 \(windows.count) 个窗口放回原处")
                                                : L("paneful: arrange \(windows.count) window(s)", "paneful:摆放 \(windows.count) 个窗口"))
                report.details.append(["kind": "paneful", "id": "paneful.layout", "before": "current layout",
                                       "after": restoring ? "saved layout" : "\(windows.count) window(s)"])
            } else {
                // The Dock just restarted (auto-hide changes the usable screen area); let it settle first.
                if !restart.isEmpty { Thread.sleep(forTimeInterval: 1.5) }
                let (entry, ok) = restoring ? Paneful.restore(windows) : Paneful.apply(windows)
                report.changed.append(Paneful.line(entry))
                report.details.append(entry)
                if !ok { report.problems.append("paneful: \(entry["error"] ?? "")") }
            }
        }
        return report
    }
}
