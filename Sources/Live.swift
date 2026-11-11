// The features the running app provides itself: instant Space switching,
// keeping the Mac awake, and opening at login. `apply` is safe to call as
// often as you like; it only changes what differs from what you asked for.

import AppKit
import IOKit.pwr_mgt
import ServiceManagement

final class Live {
    static let shared = Live()

    struct State { var active: Bool; var note: String }
    private(set) var states: [String: State] = [:]
    private(set) var config = Config()
    /// Called on the main thread whenever a state changed.
    var onChange: (() -> Void)?

    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var gesturesReady = false
    private var spaceObserver: NSObjectProtocol?

    var trusted: Bool { AXIsProcessTrusted() }
    var needsPermission: Bool { wantsSpaces && !trusted }
    private var wantsSpaces: Bool { on("spaces.instant") || on("spaces.instantSwipe") }
    private func on(_ id: String) -> Bool { config.live[id] ?? false }

    /// `askForPermission` shows the system's Accessibility prompt if it is needed. Only pass true for a click by the user.
    func apply(_ newConfig: Config, askForPermission: Bool = false) {
        config = newConfig
        applyAwake()
        applySpaces(askForPermission: askForPermission)
        applyLoginItem()
        writeStatus()
        onChange?()
    }

    // MARK: Keep awake

    private func hold(_ type: String, _ id: inout IOPMAssertionID, _ wanted: Bool) -> Bool {
        if wanted, id == 0 {
            var new: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "Knobs: keep awake" as CFString, &new) == kIOReturnSuccess { id = new }
        } else if !wanted, id != 0 {
            IOPMAssertionRelease(id)
            id = 0
        }
        return id != 0
    }

    private func applyAwake() {
        let display = hold(kIOPMAssertionTypePreventUserIdleDisplaySleep, &displayAssertion, on("awake.display"))
        let system = hold(kIOPMAssertionTypePreventUserIdleSystemSleep, &systemAssertion, on("awake.system"))
        states["awake.display"] = State(active: display, note: on("awake.display") && !display ? L("macOS refused the request", "macOS 拒绝了这个请求") : "")
        states["awake.system"] = State(active: system, note: on("awake.system") && !system ? L("macOS refused the request", "macOS 拒绝了这个请求") : "")
    }

    // MARK: Instant Spaces

    private func applySpaces(askForPermission: Bool) {
        let keys = on("spaces.instant"), swipe = on("spaces.instantSwipe")
        guard keys || swipe else {
            stopSpaces()
            states["spaces.instant"] = State(active: false, note: "")
            states["spaces.instantSwipe"] = State(active: false, note: "")
            return
        }
        guard trusted else {
            stopSpaces()
            if askForPermission {
                let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            }
            let note = L("waiting for the Accessibility permission (System Settings > Privacy & Security > Accessibility > Knobs)", "等待辅助功能权限(系统设置 > 隐私与安全性 > 辅助功能 > 打开 Knobs)")
            states["spaces.instant"] = State(active: false, note: keys ? note : "")
            states["spaces.instantSwipe"] = State(active: false, note: swipe ? note : "")
            return
        }
        if !gesturesReady {
            gesturesReady = iss_init()
            if gesturesReady, spaceObserver == nil {
                spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in iss_reset_predictions() }
            }
        }
        let failed = gesturesReady ? "" : L("could not start the event tap", "无法启动手势监听")
        iss_set_swipe_override(gesturesReady && swipe)

        var keysActive = false
        if keys, gesturesReady {
            var bindings: [(combo: KeyCombo, action: () -> Void)] = []
            for name in Config.shortcutNames {
                guard let text = config.shortcuts[name], let combo = KeyCombo.parse(text) else { continue }
                switch name {
                case "spaceLeft": bindings.append((combo, { _ = iss_switch(ISSDirectionLeft) }))
                case "spaceRight": bindings.append((combo, { _ = iss_switch(ISSDirectionRight) }))
                default:
                    let index = UInt32(name.dropFirst(5)).map { $0 - 1 } ?? 0
                    bindings.append((combo, { _ = iss_switch_to_index(index) }))
                }
            }
            KeyTap.shared.bindings = bindings
            keysActive = KeyTap.shared.start()
        } else {
            KeyTap.shared.stop()
        }
        states["spaces.instant"] = State(active: keysActive, note: keys && !keysActive ? (failed.isEmpty ? L("could not start the key tap", "无法启动按键监听") : failed) : "")
        states["spaces.instantSwipe"] = State(active: gesturesReady && swipe, note: swipe ? failed : "")
    }

    private func stopSpaces() {
        KeyTap.shared.stop()
        if gesturesReady {
            iss_set_swipe_override(false)
            iss_destroy()
            gesturesReady = false
        }
    }

    // MARK: Open at login

    private func applyLoginItem() {
        let id = "app.launchAtLogin"
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            states[id] = State(active: false, note: on(id) ? L("only works from the installed Knobs.app", "只有安装后的 Knobs.app 才能使用") : "")
            return
        }
        let service = SMAppService.mainApp
        var note = ""
        if on(id), service.status != .enabled {
            do { try service.register() } catch { note = L("macOS refused: \(error.localizedDescription)", "macOS 拒绝了:\(error.localizedDescription)") }
        } else if !on(id), service.status == .enabled {
            try? service.unregister()
        }
        states[id] = State(active: service.status == .enabled, note: note)
    }

    // MARK: Status file, read by the `knobs` command

    private func writeStatus() {
        var live: [String: Any] = [:]
        for (id, s) in states { live[id] = ["active": s.active, "note": s.note] }
        let obj: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "accessibility": trusted, "live": live]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? FileManager.default.createDirectory(atPath: ConfigStore.dir, withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: ConfigStore.statusPath), options: .atomic)
        }
    }
}
