// The settings window. Every row is drawn from the catalog, so a new catalog
// entry shows up here without any UI work.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class Model: ObservableObject {
    /// What each setting is right now (the macOS default when the key is unset).
    @Published var values: [String: Value] = [:]
    /// Settings that differ from "never touched": a written key, or a live feature that is on.
    @Published var customized: Set<String> = []
    @Published var notes: [String: String] = [:]
    @Published var needsPermission = false
    /// Live features that are really running right now, not merely switched on.
    @Published var active: Set<String> = []
    @Published var search = ""
    @Published var selection: String? = "all"
    @Published var banner: String?
    /// The banner reports a problem rather than news; it is drawn in orange.
    @Published var bannerIsError = false
    /// The banner follows a change that can be undone, so it offers an Undo button.
    @Published var bannerCanUndo = false
    /// Snapshots on disk: how many steps `knobs undo` (and the Undo button) can go back.
    @Published var undoSteps = 0
    /// Slider positions and text drafts that are not committed yet, by setting id.
    /// (Kept here rather than in @State: the command line toolchain has no SwiftUI macro plugin.)
    @Published var dragging: [String: Double] = [:]
    @Published var drafts: [String: String] = [:]

    func refresh() {
        var values: [String: Value] = [:]
        var customized: Set<String> = []
        var notes: [String: String] = [:]
        for s in catalog {
            let now = Engine.current(s)
            if let v = now ?? s.systemDefault { values[s.id] = v }
            if case .live = s.backing {
                if now == .bool(true) { customized.insert(s.id) }
                if let note = Live.shared.states[s.id]?.note, !note.isEmpty { notes[s.id] = note }
            } else if now != nil {
                customized.insert(s.id)
            }
        }
        self.values = values
        self.customized = customized
        self.notes = notes
        self.needsPermission = Live.shared.needsPermission
        self.active = Set(Live.shared.states.filter { $0.value.active }.keys)
        self.undoSteps = Profile.backups().count
    }

    func show(_ text: String, error: Bool = false, canUndo: Bool = false) {
        banner = text
        bannerIsError = error
        bannerCanUndo = canUndo
    }

    /// Every change from the window saves a snapshot first, the same as `knobs set`,
    /// so the Undo button and `knobs undo` share one history.
    private func snapshotIfChanging(_ s: Setting, to value: Value?) -> Bool {
        let now = Engine.current(s)
        if case .live = s.backing, (now?.asBool ?? false) == (value?.asBool ?? false) { return false }
        if let value, let wanted = try? Engine.validate(s, value), wanted == now { return false }
        if value == nil, now == nil { return false }
        let what = value.map { "\(s.id) \($0)" } ?? L("\(s.id) back to the default", "\(s.id) 恢复默认")
        return Profile.saveSnapshot(reason: L("window: ", "窗口:") + what) != nil
    }

    func set(_ s: Setting, _ value: Value) {
        do {
            _ = try Engine.validate(s, value)
            _ = snapshotIfChanging(s, to: value)
            let restart = try Engine.set(s, value)
            banner = nil
            if case .live = s.backing { AppDelegate.shared.reload(askForPermission: true) }
            refresh()
            // Restarting the Dock or Finder takes a moment; keep the window responsive meanwhile.
            if !restart.isEmpty { DispatchQueue.global(qos: .userInitiated).async { Prefs.restart(restart) } }
        } catch {
            show("\(error)", error: true)
            refresh()
        }
    }

    func reset(_ s: Setting) {
        let saved = snapshotIfChanging(s, to: nil)
        let restart = Engine.reset(s)
        if case .live = s.backing { AppDelegate.shared.reload() }
        refresh()
        if saved { show(L("\(s.title): back to the macOS default.", "\(s.title):已恢复为 macOS 默认。"), canUndo: true) }
        if !restart.isEmpty { DispatchQueue.global(qos: .userInitiated).async { Prefs.restart(restart) } }
    }

    /// Step back one change, whoever made it: this window, the menu bar, `knobs` or an agent.
    func undo() {
        let r = Changes.undo()
        AppDelegate.shared.reload()
        refresh()
        if let error = r.error { show(error, error: true); return }
        let restored = r.report.changed
        var text = L("Undid \"\(r.reason)\".", "已撤销“\(r.reason)”。")
        if !restored.isEmpty { text += " " + restored.prefix(4).joined(separator: "; ") + (restored.count > 4 ? " …" : "") }
        if !r.report.problems.isEmpty { text += " " + r.report.problems.joined(separator: "; ") }
        show(text, error: !r.report.problems.isEmpty, canUndo: undoSteps > 0)
    }

    var visible: [(category: Category, settings: [Setting])] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return Category.allCases.compactMap { c in
            if let selection, selection != "all", selection != "changed", selection != c.rawValue { return nil }
            let rows = catalog.filter { s in
                guard s.category == c else { return false }
                if selection == "changed", !customized.contains(s.id) { return false }
                if needle.isEmpty { return true }
                return [s.title, s.detail, s.id, s.keyDescription].contains { $0.lowercased().contains(needle) }
            }
            return rows.isEmpty ? nil : (c, rows)
        }
    }

    func changedCount(_ c: Category) -> Int { catalog.filter { $0.category == c && customized.contains($0.id) }.count }

    /// One line for a live feature: running, waiting, or off.
    func liveSummary(_ id: String) -> (text: String, color: Color) {
        if active.contains(id) { return (L("Active", "已生效"), .green) }
        if values[id]?.asBool == true { return (notes[id] == nil ? L("Starting…", "启动中…") : L("Waiting for permission", "等待授权"), .orange) }
        return (L("Off", "未开启"), .secondary)
    }

    // MARK: Export, import, agent prompt

    func exportProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "my-mac.knobs.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Profile.exportText().write(to: url, atomically: true, encoding: .utf8)
            show(L("Exported to \((url.path as NSString).abbreviatingWithTildeInPath). Give this file to an agent on a new Mac.", "已导出到 \((url.path as NSString).abbreviatingWithTildeInPath)。换新电脑时把这个文件交给 agent 即可。"))
        } catch { show(L("Could not write the file.", "无法写入文件。"), error: true) }
    }

    func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        do {
            let preview = try Profile.apply(text: text, dryRun: true)
            guard !preview.changed.isEmpty else {
                show(L("Nothing to change: this Mac already matches the profile.", "无需更改:这台 Mac 已经和配置文件一致。"))
                return
            }
            let alert = NSAlert()
            alert.messageText = L("Apply \(preview.changed.count) changes?", "应用 \(preview.changed.count) 项更改?")
            alert.informativeText = (preview.changed.prefix(25) + (preview.changed.count > 25 ? ["…"] : []) + preview.skipped + preview.problems).joined(separator: "\n")
            alert.addButton(withTitle: L("Apply", "应用"))
            alert.addButton(withTitle: L("Cancel", "取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let done = try Profile.apply(text: text, dryRun: false, reason: L("window: import ", "窗口:导入 ") + url.lastPathComponent)
            AppDelegate.shared.reload(askForPermission: true)
            refresh()
            show(L("Applied \(done.changed.count) changes. A snapshot was saved first, so Undo puts them all back.", "已应用 \(done.changed.count) 项更改。应用前已自动存了快照,点“撤销”即可全部恢复。")
                 + ((done.skipped + done.problems).isEmpty ? "" : " " + (done.skipped + done.problems).joined(separator: "; ")), error: !done.problems.isEmpty, canUndo: true)
        } catch { show("\(error)", error: true) }
    }

    func copyAgentPrompt() {
        let text = """
        You can read and change my macOS settings with the `knobs` command (\(Profile.repoURL)).
        Run `~/.local/bin/knobs list --json` to see every setting with its id, meaning, current value and when a change takes effect.
        Use `knobs set <id> <value>` to change one, `knobs reset <id>` to hand it back to macOS, and `knobs describe <id>` for details.
        Every change saves a snapshot first; `knobs undo` steps back one change. Add --json to any command for machine-readable output.
        Tell me what you changed and what each setting does. Ask before changing anything I did not mention.
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show(L("Copied. Paste it to your agent.", "已复制,粘贴给你的 agent 即可。"))
    }
}

// MARK: - Views

/// Icons come from Lucide (ISC license), bundled as SVG and drawn as templates so they
/// take the text colour. One icon family, one colour.
private var iconCache: [String: NSImage] = [:]
func lucide(_ name: String, size: CGFloat = 16) -> NSImage {
    let key = "\(name)@\(size)"
    if let hit = iconCache[key] { return hit }
    var image = NSImage(systemSymbolName: "circle", accessibilityDescription: name) ?? NSImage()
    if let url = Bundle.main.resourceURL?.appendingPathComponent("icons/\(name).svg"),
       let text = try? String(contentsOf: url, encoding: .utf8),
       let svg = NSImage(data: Data(text.replacingOccurrences(of: "currentColor", with: "black")
                                        .replacingOccurrences(of: "stroke-width=\"2\"", with: "stroke-width=\"1.75\"").utf8)) {
        svg.size = NSSize(width: size, height: size)
        image = svg
    }
    image.isTemplate = true
    iconCache[key] = image
    return image
}

struct IconLabel: View {
    let title: String
    let icon: String
    var body: some View {
        Label { Text(title) } icon: { Image(nsImage: lucide(icon)).foregroundStyle(.secondary) }
    }
}

private let cardFill = Color(nsColor: .controlBackgroundColor)
private let cardStroke = Color(nsColor: .separatorColor).opacity(0.55)

struct MainView: View {
    @ObservedObject var model: Model

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                // The tag goes last: a modifier after .tag (such as .badge) can hide it from the
                // List, and the row then cannot be selected.
                IconLabel(title: L("All settings", "全部设置"), icon: "layout-grid").tag("all")
                IconLabel(title: L("My setup", "我的设置"), icon: "pencil")
                    .badge(model.customized.count).tag("changed")
                Section(L("Groups", "分组")) {
                    ForEach(Category.allCases, id: \.rawValue) { c in
                        IconLabel(title: c.title, icon: c.symbol)
                            .badge(model.changedCount(c)).tag(c.rawValue)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
            .safeAreaInset(edge: .bottom) { SidebarFooter(model: model) }
        } detail: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if model.needsPermission { PermissionBanner() }
                    if let banner = model.banner {
                        MessageBanner(text: banner, isError: model.bannerIsError,
                                      undo: model.bannerCanUndo && model.undoSteps > 0 ? { model.undo() } : nil) { model.banner = nil }
                    }
                    if model.selection == "all", model.search.isEmpty { QuickBar(model: model) }
                    if model.selection == "changed" { SetupIntro(model: model) }
                    let groups = model.visible
                    if groups.isEmpty { EmptyState(changedOnly: model.selection == "changed") }
                    ForEach(groups, id: \.category.rawValue) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            GroupHeader(category: group.category, total: group.settings.count, changed: model.changedCount(group.category))
                            VStack(spacing: 0) {
                                ForEach(Array(group.settings.enumerated()), id: \.element.id) { index, s in
                                    if index > 0 { Divider().padding(.leading, 16) }
                                    SettingRow(model: model, setting: s)
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 12).fill(cardFill))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(cardStroke))
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 20)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .searchable(text: $model.search, prompt: L("Search settings", "搜索设置"))
            .toolbar {
                ToolbarItemGroup {
                    Button { model.undo() } label: { Label { Text(L("Undo", "撤销")) } icon: { Image(nsImage: lucide("undo-2")) } }
                        .disabled(model.undoSteps == 0)
                        .keyboardShortcut("z", modifiers: .command)
                        .help(model.undoSteps == 0 ? L("Nothing to undo yet. Every change saves a snapshot first.", "还没有可撤销的。每次修改前都会先存快照。")
                              : L("Undo the last change, from here, the menu bar, the command line or an agent (\(model.undoSteps) steps)", "撤销最近一次修改,不论是在这里、菜单栏、命令行还是 agent 改的(还能撤 \(model.undoSteps) 步)"))
                    Button { model.copyAgentPrompt() } label: { Label { Text(L("Agent prompt", "Agent 提示词")) } icon: { Image(nsImage: lucide("square-terminal")) } }
                        .help(L("Copy a prompt that teaches your agent to use Knobs", "复制一段提示词,让你的 agent 学会操作 Knobs"))
                    Button { model.importProfile() } label: { Label { Text(L("Import", "导入")) } icon: { Image(nsImage: lucide("download")) } }
                        .help(L("Apply a profile exported from another Mac", "应用从另一台 Mac 导出的配置文件"))
                    Button { model.exportProfile() } label: { Label { Text(L("Export", "导出")) } icon: { Image(nsImage: lucide("upload")) } }
                        .help(L("Save all current settings and shortcuts to one file", "把当前所有设置和快捷键存成一个文件"))
                }
            }
        }
        .navigationTitle("Knobs")
    }
}

/// The three things people open Knobs for, one click away.
struct QuickBar: View {
    @ObservedObject var model: Model

    var body: some View {
        HStack(spacing: 12) {
            quickToggle("spaces.instant", symbol: "arrow-left-right", title: L("Instant Spaces", "无动画切换"))
            quickToggle("awake.display", symbol: "sun", title: L("Display awake", "屏幕常亮"))
            Button { model.selection = "changed" } label: {
                HStack(spacing: 12) {
                    icon("pencil")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("My setup", "我的设置")).font(.callout.weight(.medium)).lineLimit(1).fixedSize()
                        Text(L("\(model.customized.count) of \(catalog.count) settings", "\(catalog.count) 项中的 \(model.customized.count) 项"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(14).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(cardFill))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(cardStroke))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// One quiet colour for every icon. Colour is reserved for state: the switch and the status dot.
    private func icon(_ symbol: String) -> some View {
        Image(nsImage: lucide(symbol, size: 18)).foregroundStyle(.secondary)
            .frame(width: 22)
    }

    private func quickToggle(_ id: String, symbol: String, title: String) -> some View {
        let summary = model.liveSummary(id)
        return HStack(spacing: 12) {
            icon(symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1).fixedSize()
                HStack(spacing: 5) {
                    Circle().fill(summary.color).frame(width: 6, height: 6)
                    Text(summary.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { model.values[id]?.asBool ?? false },
                                     set: { on in if let s = catalogByID[id] { model.set(s, .bool(on)) } }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(14).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(cardStroke))
    }
}

struct GroupHeader: View {
    let category: Category
    let total: Int
    let changed: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(category.title).font(.headline)
            Spacer()
            Text(changed > 0 ? L("\(total) settings · \(changed) changed", "\(total) 项 · 已改 \(changed) 项") : L("\(total) settings", "\(total) 项"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }
}

struct SidebarFooter: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(model.needsPermission ? Color.orange : Color.green).frame(width: 7, height: 7)
            Text(model.needsPermission ? L("Needs Accessibility permission", "需要辅助功能权限")
                 : L("\(model.active.count) live features running", "\(model.active.count) 项实时功能运行中"))
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

struct EmptyState: View {
    let changedOnly: Bool
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: changedOnly ? "checkmark.circle" : "magnifyingglass").font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(changedOnly ? L("Everything is at the macOS default.", "所有设置都是 macOS 默认值。") : L("No settings match.", "没有匹配的设置。"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }
}

struct PermissionBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("One permission, once", "只需授权一次")).font(.headline)
                Text(L("Instant Space switching replaces the system shortcut, which needs the Accessibility permission. Switch Knobs on in the list; it starts working the moment you do, with no restart.",
                       "无动画切换桌面需要接管系统快捷键,所以要“辅助功能”权限。在列表里打开 Knobs 的开关即可,打开的瞬间就生效,不用重启。"))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L("Open Accessibility settings", "打开辅助功能设置")) { AppDelegate.shared.openAccessibility() }.padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
    }
}

/// What "My setup" is, in plain words, with the one thing people do with it.
struct SetupIntro: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: lucide("pencil", size: 18)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Everything on this Mac that differs from how macOS ships", "这台 Mac 上和出厂默认不一样的设置"))
                    .font(.callout.weight(.medium))
                Text(L("Changes made here, in System Settings or with `defaults write` all show up. This is exactly what Export saves for your next Mac. Reset hands a setting back to macOS.",
                       "不管是在这里、在系统设置里,还是用 `defaults write` 改的,都会列在这里。“导出”带走的正是这些,换新电脑时一键恢复。点“恢复默认”就把这一项交还给 macOS。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(L("Export…", "导出…")) { model.exportProfile() }
        }
        .padding(14).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(cardFill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(cardStroke))
    }
}

struct MessageBanner: View {
    let text: String
    var isError = false
    var undo: (() -> Void)?
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if isError { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 8)
            if let undo { Button(L("Undo", "撤销"), action: undo) }
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
                .help(L("Dismiss", "关闭"))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill((isError ? Color.orange : Color.accentColor).opacity(0.12)))
    }
}

struct Pill: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text).font(.caption2).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().strokeBorder(color.opacity(0.35)))
    }
}

struct SettingRow: View {
    @ObservedObject var model: Model
    let setting: Setting

    private var isLive: Bool { if case .live = setting.backing { return true }; return false }
    private var isChanged: Bool { model.customized.contains(setting.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(setting.title).font(.body.weight(.medium))
                    if isLive, model.active.contains(setting.id) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(L("Active", "已生效")).font(.caption).foregroundStyle(.secondary)
                    } else if isChanged, !isLive { Pill(text: L("Customized", "已自定义")) }
                    if setting.timing != .instant {
                        Pill(text: setting.timing.label)
                            .help(setting.timing == .relogin
                                  ? L("macOS only reads this when you log in. The change is saved now and shows after you log out and back in.", "macOS 只在登录时读取这一项。修改已经保存,注销重新登录后才会看到效果。")
                                  : L("Apps that are already open keep the old behaviour until you quit and reopen them.", "已经打开的 App 保持原样,退出再打开后才会用新设置。"))
                    }
                }
                Text(setting.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let note = model.notes[setting.id] {
                    Label(note, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(setting.id).font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
                    .help(setting.keyDescription)
            }
            Spacer(minLength: 12)
            if isChanged, !isLive {
                Button(L("Reset", "恢复默认")) { model.reset(setting) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help(L("Hand this setting back to macOS", "把这一项交还给 macOS 默认值"))
            }
            control
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var control: some View {
        switch setting.kind {
        case .toggle:
            Toggle("", isOn: Binding(get: { model.values[setting.id]?.asBool ?? false },
                                     set: { model.set(setting, .bool($0)) }))
                .toggleStyle(.switch).labelsHidden()
        case .choice(let options):
            let picker = Picker("", selection: Binding(get: { model.values[setting.id]?.asString ?? "" },
                                                       set: { model.set(setting, .string($0)) })) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .labelsHidden().fixedSize()
            if options.count <= 3 { picker.pickerStyle(.segmented) } else { picker.pickerStyle(.menu) }
        case .number(let min, let max, let step, let unit, let integer):
            NumberControl(model: model, id: setting.id, value: model.values[setting.id]?.asDouble, min: min, max: max, step: step, unit: unit, integer: integer) {
                model.set(setting, integer ? .int(Int($0.rounded())) : .double($0))
            }
        case .text:
            TextControl(model: model, id: setting.id, value: model.values[setting.id]?.asString ?? "") { model.set(setting, .string($0)) }
        }
    }
}

/// A slider that commits when you let go, so the Dock restarts once, not on every pixel.
struct NumberControl: View {
    @ObservedObject var model: Model
    let id: String
    let value: Double?
    let min: Double, max: Double, step: Double
    let unit: String
    let integer: Bool
    let commit: (Double) -> Void
    private var dragging: Double? { model.dragging[id] }

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: Binding(get: { dragging ?? value ?? min }, set: { model.dragging[id] = $0 }), in: min...max) { editing in
                if !editing, let d = dragging {
                    commit(Swift.min(max, Swift.max(min, (d / step).rounded() * step)))
                    model.dragging[id] = nil
                }
            }
            .controlSize(.small).frame(width: 150)
            Text(label).font(.callout.monospacedDigit()).foregroundStyle(dragging == nil ? .secondary : .primary)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private var label: String {
        guard let v = dragging ?? value else { return L("default", "默认") }
        let rounded = (v / step).rounded() * step
        let number = integer ? String(Int(rounded)) : String(format: step < 0.01 ? "%.3f" : "%.2f", rounded)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

struct TextControl: View {
    @ObservedObject var model: Model
    let id: String
    let value: String
    let commit: (String) -> Void

    var body: some View {
        TextField(L("default", "默认"), text: Binding(get: { model.drafts[id] ?? value }, set: { model.drafts[id] = $0 }))
            .textFieldStyle(.roundedBorder).frame(width: 230)
            .onSubmit {
                let text = model.drafts[id] ?? value
                model.drafts[id] = nil
                commit(text)
            }
    }
}
