// The app: a menu bar item, the settings window, and the loop that keeps the
// live features in step with the config file.

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    static var shared: AppDelegate!
    let model = Model()
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var lastConfig = Config()
    private var lastTrusted = false

    func applicationDidFinishLaunching(_ note: Notification) {
        AppDelegate.shared = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = lucide("sliders-horizontal", size: 18)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        Live.shared.onChange = { [weak self] in self?.model.refresh() }
        reload()

        // A change from the command line arrives here at once; the timer is the safety net
        // and also notices the moment the Accessibility permission is granted.
        DistributedNotificationCenter.default().addObserver(forName: ConfigStore.changed, object: nil, queue: .main) { [weak self] _ in self?.reload() }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if ConfigStore.load() != self.lastConfig || Live.shared.trusted != self.lastTrusted { self.reload() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.model.refresh() }

        if !CommandLine.arguments.contains("--background") { showWindow() }
    }

    func reload(askForPermission: Bool = false) {
        lastConfig = ConfigStore.load()
        lastTrusted = Live.shared.trusted
        Live.shared.apply(lastConfig, askForPermission: askForPermission)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    // MARK: Window

    @objc func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Knobs"
            w.contentViewController = NSHostingController(rootView: MainView(model: model))
            w.setContentSize(NSSize(width: 940, height: 660))
            w.minSize = NSSize(width: 720, height: 420)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("KnobsMain")
            window = w
        }
        model.refresh()
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Menu bar

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for id in ["spaces.instant", "spaces.instantSwipe", "awake.display", "awake.system"] {
            guard let s = catalogByID[id] else { continue }
            let item = NSMenuItem(title: s.title, action: #selector(toggleLive(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = (Engine.current(s)?.asBool ?? false) ? .on : .off
            menu.addItem(item)
        }
        if Live.shared.needsPermission {
            menu.addItem(.separator())
            let item = NSMenuItem(title: L("Grant Accessibility permission…", "授予辅助功能权限…"), action: #selector(openAccessibility), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let steps = Profile.backups().count
        let undo = NSMenuItem(title: steps == 0 ? L("Nothing to undo", "没有可撤销的") : L("Undo last change", "撤销上一次修改"),
                              action: steps == 0 ? nil : #selector(undoLast), keyEquivalent: "")
        undo.target = self
        undo.toolTip = steps == 0 ? nil : Profile.reason(ofSnapshot: Profile.backups()[0])
        menu.addItem(undo)
        let open = NSMenuItem(title: L("Open Knobs…", "打开 Knobs…"), action: #selector(showWindow), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)
        menu.addItem(NSMenuItem(title: L("Quit Knobs", "退出 Knobs"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleLive(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let s = catalogByID[id] else { return }
        model.set(s, .bool(item.state != .on))
    }

    @objc private func undoLast() {
        model.undo()
    }

    @objc func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
