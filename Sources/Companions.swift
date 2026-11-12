// Other tools a profile or scene can drive, through their own agent interfaces.
//
// Knobs never writes another tool's internal files to change its state. It calls the tool's
// MCP server (`overbright mcp`), which does the work and reads the result back, so a scene
// can prove the brightness really arrived and `knobs undo` can put it back.

import Foundation

/// A minimal MCP client: start `<tool> mcp`, initialize, make one tool call, close.
enum MCPClient {
    /// One MCP tool call over stdio: initialize, then the call. Returns the tool's result
    /// object and whether it reported an error, or nil if the server could not be reached.
    static func call(_ path: String, _ tool: String, _ arguments: [String: Any] = [:], timeout: TimeInterval = 30) -> (result: [String: Any], isError: Bool)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["mcp"]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }

        let messages: [[String: Any]] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "knobs", "version": "1"]]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": tool, "arguments": arguments]],
        ]
        for m in messages {
            guard let data = try? JSONSerialization.data(withJSONObject: m) else { continue }
            input.fileHandleForWriting.write(data + Data("\n".utf8))
        }

        // Read until the answer to id 2 arrives, then close stdin so the server exits.
        var buffer = Data()
        var answer: [String: Any]?
        let deadline = Date().addingTimeInterval(timeout)
        let reader = output.fileHandleForReading
        while answer == nil, Date() < deadline {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], obj["id"] as? Int == 2 { answer = obj }
            }
        }
        try? input.fileHandleForWriting.close()
        if p.isRunning { p.terminate() }
        p.waitUntilExit()

        guard let result = answer?["result"] as? [String: Any] else { return nil }
        let isError = result["isError"] as? Bool ?? false
        if let structured = result["structuredContent"] as? [String: Any] { return (structured, isError) }
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? ["text": text]
        return (obj, isError)
    }

}

enum Overbright {
    /// The `overbright` command, if installed.
    static var path: String? {
        let candidates = [expandTilde("~/.local/bin/overbright"), "/opt/homebrew/bin/overbright", "/usr/local/bin/overbright"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var installed: Bool { path != nil }

    /// One call to `overbright mcp`, or nil if it is not installed or did not answer.
    static func call(_ tool: String, _ arguments: [String: Any] = [:], timeout: TimeInterval = 30) -> (result: [String: Any], isError: Bool)? {
        guard let path else { return nil }
        return MCPClient.call(path, tool, arguments, timeout: timeout)
    }

    /// Where the built-in display sits on Overbright's scale: 0–100 is the backlight, above 100 the boost.
    static func currentPercent() -> Double? {
        guard let path else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["status", "--json"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["scale"] as? NSNumber)?.doubleValue
    }

    /// Sets the scale and waits for Overbright's readback. Returns a report entry for --json and MCP.
    static func set(percent: Double) -> (entry: [String: Any], ok: Bool) {
        let before = currentPercent()
        var entry: [String: Any] = ["kind": "overbright", "id": "overbright.percent", "before": before ?? NSNull(), "after": percent]
        guard let (result, isError) = call("set_brightness", ["percent": percent]) else {
            entry["verified"] = false
            entry["error"] = L("Overbright did not answer (is the Overbright app running?)", "Overbright 没有响应(Overbright 应用在运行吗?)")
            return (entry, false)
        }
        let readback = result["readback"] as? String ?? "unknown"
        entry["readback"] = readback
        if let nits = result["panelNits"] { entry["panelNits"] = nits }
        // "notDirect" means the boost is drawn on screen, where the backlight cannot prove it.
        entry["verified"] = readback == "reached" || readback == "restored"
        if isError { entry["error"] = (result["error"] as? String) ?? L("Overbright could not confirm the change (readback: \(readback))", "Overbright 无法确认这次修改(回读:\(readback))") }
        return (entry, !isError)
    }
}

enum Paneful {
    /// The `paneful` command, if installed.
    static var path: String? {
        let candidates = [expandTilde("~/.local/bin/paneful"), "/opt/homebrew/bin/paneful", "/usr/local/bin/paneful",
                          expandTilde("~/Applications/Paneful.app/Contents/MacOS/Paneful"), "/Applications/Paneful.app/Contents/MacOS/Paneful"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var installed: Bool { path != nil }

    private static func call(_ tool: String, _ arguments: [String: Any] = [:]) -> (result: [String: Any], isError: Bool)? {
        guard let path else { return nil }
        return MCPClient.call(path, tool, arguments)
    }

    private static let notRunning = L("Paneful did not answer (is the Paneful app running?)", "Paneful 没有响应(Paneful 应用在运行吗?)")

    /// Problems with a layout before anything moves: Paneful needs an app or a title to pick each
    /// window, and positions are fractions of the screen.
    static func problems(_ layout: [[String: Any]]) -> [String] {
        if layout.isEmpty { return [L("the layout lists no windows", "布局里没有窗口")] }
        var out: [String] = []
        for (i, w) in layout.enumerated() {
            let n = i + 1
            let named = [w["app"], w["title"]].contains { ($0 as? String).map { !$0.isEmpty } ?? false }
            if !named { out.append(L("window \(n): give \"app\" or \"title\"", "第 \(n) 个窗口:要写 \"app\" 或 \"title\"")) }
            for key in ["x", "y", "w", "h"] {
                guard let n = w[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else {
                    out.append(L("window \(n): \(key) must be a number from 0 to 1", "第 \(n) 个窗口:\(key) 必须是 0 到 1 之间的数")); continue
                }
                let v = n.doubleValue
                if v < 0 || v > 1 || ((key == "w" || key == "h") && v == 0) {
                    out.append(L("window \(n): \(key) \(v) is outside 0–1", "第 \(n) 个窗口:\(key) \(v) 不在 0 到 1 之间"))
                }
            }
        }
        return out
    }

    /// Where every window is now, for the snapshot. Nil if Paneful is not running.
    static func saveLayout() -> [[String: Any]]? {
        guard let (result, isError) = call("save_layout"), !isError else { return nil }
        return result["layout"] as? [[String: Any]]
    }

    /// A short, title-free account of one placed window, so agent transcripts do not carry window titles.
    private static func summary(_ windows: [[String: Any]]) -> [[String: Any]] {
        windows.map { ["app": $0["app"] ?? "", "matchesTarget": $0["matchesTarget"] ?? NSNull()] }
    }

    /// Places windows (`apply_layout`) and returns Paneful's readback as a report entry.
    static func apply(_ layout: [[String: Any]]) -> (entry: [String: Any], ok: Bool) {
        var entry: [String: Any] = ["kind": "paneful", "id": "paneful.layout", "after": "\(layout.count) window(s)"]
        guard let (result, isError) = call("apply_layout", ["windows": layout]) else {
            entry["verified"] = false; entry["error"] = notRunning; return (entry, false)
        }
        return finish(&entry, result, isError, strict: true)
    }

    /// Puts windows back where `saveLayout` found them (`restore_layout`).
    static func restore(_ layout: [[String: Any]]) -> (entry: [String: Any], ok: Bool) {
        var entry: [String: Any] = ["kind": "paneful", "id": "paneful.layout", "after": "saved layout"]
        guard let (result, isError) = call("restore_layout", ["layout": layout]) else {
            entry["verified"] = false; entry["error"] = notRunning; return (entry, false)
        }
        // A window closed since the snapshot cannot come back; that alone is not a failed undo.
        return finish(&entry, result, isError, strict: false)
    }

    private static func finish(_ entry: inout [String: Any], _ result: [String: Any], _ isError: Bool, strict: Bool) -> (entry: [String: Any], ok: Bool) {
        let windows = result["windows"] as? [[String: Any]] ?? []
        let skipped = result["skipped"] as? [[String: Any]] ?? []
        let off = windows.filter { $0["matchesTarget"] as? Bool == false }.count
        entry["windows"] = summary(windows)
        entry["placed"] = windows.count
        entry["skipped"] = skipped.map { ["app": $0["app"] ?? "", "reason": $0["reason"] ?? ""] }
        let ok: Bool
        if result["windows"] == nil {
            ok = false
            entry["error"] = (result["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (result["error"] as? String) ?? notRunning
        } else if strict {
            ok = !isError && result["verified"] as? Bool == true
        } else {
            ok = off == 0 && skipped.allSatisfy { $0["reason"] as? String == "window not found" }
        }
        entry["verified"] = ok
        if !ok, entry["error"] == nil {
            var why: [String] = []
            if off > 0 { why.append(L("\(off) window(s) did not reach the requested frame", "\(off) 个窗口没有到达要求的位置")) }
            if !skipped.isEmpty { why.append(L("\(skipped.count) skipped", "跳过 \(skipped.count) 个")) }
            entry["error"] = L("Paneful could not confirm the layout", "Paneful 无法确认窗口布局") + (why.isEmpty ? "" : ": " + why.joined(separator: ", "))
        }
        return (entry, ok)
    }

    /// One line for the human report.
    static func line(_ entry: [String: Any]) -> String {
        let placed = entry["placed"] as? Int ?? 0
        let skipped = (entry["skipped"] as? [Any])?.count ?? 0
        let state = (entry["verified"] as? Bool == true) ? L("verified", "已回读确认") : L("not verified", "未确认")
        return "paneful: \(placed) " + L("window(s) placed", "个窗口已摆放") + (skipped > 0 ? L(", \(skipped) skipped", ",跳过 \(skipped) 个") : "") + "  (\(state))"
    }
}
