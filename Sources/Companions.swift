// Other tools a profile or scene can drive, through their own agent interfaces.
//
// Knobs never writes another tool's internal files to change its state. It calls the tool's
// MCP server (`overbright mcp`), which does the work and reads the result back, so a scene
// can prove the brightness really arrived and `knobs undo` can put it back.

import Foundation

enum Overbright {
    /// The `overbright` command, if installed.
    static var path: String? {
        let candidates = [expandTilde("~/.local/bin/overbright"), "/opt/homebrew/bin/overbright", "/usr/local/bin/overbright"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var installed: Bool { path != nil }

    /// One MCP tool call over stdio: initialize, then the call. Returns the tool's result
    /// object and whether it reported an error, or nil if the server could not be reached.
    static func call(_ tool: String, _ arguments: [String: Any] = [:], timeout: TimeInterval = 30) -> (result: [String: Any], isError: Bool)? {
        guard let path else { return nil }
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
