// Shortcut text such as "ctrl+left", and the event tap that catches those keys
// before macOS starts its own (animated) Space switch.

import AppKit
import Carbon.HIToolbox

struct KeyCombo: Equatable {
    let code: Int64
    let flags: CGEventFlags

    static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    private static let named: [String: Int] = [
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "space": kVK_Space, "tab": kVK_Tab, "return": kVK_Return, "enter": kVK_Return, "escape": kVK_Escape, "esc": kVK_Escape,
        "delete": kVK_Delete, "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G,
        "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N,
        "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
        "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]

    /// "ctrl+left", "ctrl+alt+1", "cmd+shift+]". At least one modifier is required.
    static func parse(_ text: String) -> KeyCombo? {
        var flags: CGEventFlags = []
        var code: Int?
        for part in text.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "alt", "opt", "option", "⌥": flags.insert(.maskAlternate)
            case "shift", "⇧": flags.insert(.maskShift)
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            default:
                guard code == nil, let c = named[part] else { return nil }
                code = c
            }
        }
        guard let code, !flags.isEmpty else { return nil }
        return KeyCombo(code: Int64(code), flags: flags)
    }

    func matches(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventKeycode) == code
            && event.flags.intersection(KeyCombo.modifierMask) == flags
    }
}

/// Swallows the configured shortcuts and runs our handler instead.
/// Needs the Accessibility permission. While disabled, every key reaches macOS untouched.
final class KeyTap {
    static let shared = KeyTap()
    var bindings: [(combo: KeyCombo, action: () -> Void)] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        if tap != nil { return true }
        let callback: CGEventTapCallBack = { _, type, event, _ in
            let me = KeyTap.shared
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown, let hit = me.bindings.first(where: { $0.combo.matches(event) }) else {
                return Unmanaged.passUnretained(event)
            }
            DispatchQueue.main.async(execute: hit.action)
            return nil
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                          callback: callback, userInfo: nil) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        self.tap = nil
        source = nil
    }
}
