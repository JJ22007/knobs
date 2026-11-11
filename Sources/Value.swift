// A setting's value, and how it travels between JSON, the command line and
// the macOS preference system.

import Foundation

enum Value: Equatable, CustomStringConvertible {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    /// From a decoded JSON or property list object.
    init?(any: Any?) {
        guard let any else { return nil }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else if CFNumberIsFloatType(n) { self = .double(n.doubleValue) }
            else { self = .int(n.intValue) }
        } else if let s = any as? String {
            self = .string(s)
        } else {
            return nil
        }
    }

    /// For JSONSerialization and CFPreferences alike.
    var any: Any {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        }
    }

    var description: String {
        switch self {
        case .bool(let b): return b ? "on" : "off"
        case .int(let i): return String(i)
        case .double(let d): return String(format: "%g", d)
        case .string(let s): return s
        }
    }

    var asBool: Bool? {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .string(let s): return ["1", "true", "yes", "on"].contains(s.lowercased()) ? true
            : ["0", "false", "no", "off"].contains(s.lowercased()) ? false : nil
        case .double: return nil
        }
    }

    var asDouble: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .string(let s): return Double(s)
        case .bool: return nil
        }
    }

    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

/// English or Chinese, following the system language. KNOBS_LANG=en or zh overrides it,
/// which is handy for scripts that want stable output.
let prefersChinese: Bool = (ProcessInfo.processInfo.environment["KNOBS_LANG"]
    ?? Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
func L(_ en: String, _ zh: String) -> String { prefersChinese ? zh : en }

func expandTilde(_ path: String) -> String { (path as NSString).expandingTildeInPath }
