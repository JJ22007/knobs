// `knobs mcp`: the same catalog and the same checked writes, as a Model Context Protocol
// server on stdin/stdout (JSON-RPC 2.0, one message per line).
//
// Read-only by default. Writes (set, reset, apply, undo) need `knobs mcp --allow-write`,
// and a dry run is always allowed. Every write saves a snapshot first and reports the
// value read back from macOS, so an agent can say what really changed and undo it.

import Foundation

struct MCPServer {
    let allowWrite: Bool

    private static let protocolVersion = "2025-06-18"

    private var instructions: String {
        """
        Knobs changes macOS settings safely. Call list_settings first: every setting has an id, a plain description, \
        accepted values, the macOS default and when a change takes effect (instant, newWindows = apps opened from now on, \
        relogin = after logging out and back in). Tell the user about anything that is not instant. \
        Writes save a snapshot first and return the value read back from macOS (verified); undo steps back one change. \
        Never use sudo or `defaults write` for a setting Knobs has. \
        \(allowWrite ? "Writes are enabled." : "This server is read-only: set_settings, reset_settings and apply_profile only work with dryRun true. The user can enable writes by starting `knobs mcp --allow-write`.")
        """
    }

    // MARK: Tools

    private struct Tool {
        let name: String
        let description: String
        let schema: [String: Any]
        let writes: Bool
    }

    private static func object(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        var o: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { o["required"] = required }
        return o
    }

    private static let dryRunProperty: [String: Any] = ["type": "boolean", "description": "Only report what would change. Allowed even when the server is read-only."]

    private static let tools: [Tool] = [
        Tool(name: "list_settings",
             description: "Every setting with its id, meaning, accepted values, current value, macOS default and when a change takes effect.",
             schema: object(["category": ["type": "string", "enum": Category.allCases.map { $0.rawValue }],
                             "changedOnly": ["type": "boolean", "description": "Only settings that differ from the macOS default."]]),
             writes: false),
        Tool(name: "describe_setting", description: "One setting in detail.",
             schema: object(["id": ["type": "string"]], required: ["id"]), writes: false),
        Tool(name: "get_status",
             description: "Whether the Knobs app is running, whether the Accessibility permission is granted, the state of each live feature, and how many undo steps exist.",
             schema: object([:]), writes: false),
        Tool(name: "verify_catalog",
             description: "Read-only check: for every key already written on this Mac, does macOS store it in the shape the catalog expects? Lists mismatches; unset keys cannot be checked.",
             schema: object([:]), writes: false),
        Tool(name: "list_snapshots", description: "The undo history, newest first, with what each snapshot was taken before.",
             schema: object([:]), writes: false),
        Tool(name: "set_settings",
             description: "Change one or more settings. Values: true/false for switches, a number, or one of the listed choices. Saves one snapshot first, reads every value back, and returns before, after, verified and takesEffect for each.",
             schema: object(["changes": ["type": "object", "description": "Setting id to new value, e.g. {\"dock.autohide\": true, \"dock.autohideDelay\": 0}",
                                         "additionalProperties": ["type": ["boolean", "number", "string"]]],
                             "dryRun": dryRunProperty], required: ["changes"]),
             writes: true),
        Tool(name: "reset_settings", description: "Hand settings back to the macOS default. Saves a snapshot first.",
             schema: object(["ids": ["type": "array", "items": ["type": "string"]], "dryRun": dryRunProperty], required: ["ids"]),
             writes: true),
        Tool(name: "apply_profile",
             description: "Apply a Knobs profile: a file path, an https link or a bundled preset name (snappy, developer, focus, presenter). Run with dryRun first and show the user the list.",
             schema: object(["profile": ["type": "string"], "dryRun": dryRunProperty], required: ["profile"]),
             writes: true),
        Tool(name: "undo", description: "Undo the most recent change made with Knobs (from an agent, the command line or the window). Call again to step further back.",
             schema: object([:]), writes: true),
    ]

    private func toolList() -> [[String: Any]] {
        Self.tools.map { t in
            ["name": t.name, "description": t.description, "inputSchema": t.schema,
             "annotations": ["readOnlyHint": !t.writes, "destructiveHint": false, "idempotentHint": t.name != "undo", "openWorldHint": t.name == "apply_profile"]]
        }
    }

    /// Returns the result object and whether it is an error.
    private func call(_ name: String, _ args: [String: Any]) -> ([String: Any], Bool) {
        guard let tool = Self.tools.first(where: { $0.name == name }) else { return (["ok": false, "errors": ["unknown tool \(name)"]], true) }
        let dryRun = args["dryRun"] as? Bool ?? false
        if tool.writes, !allowWrite, !dryRun {
            return (["ok": false, "errors": ["This Knobs MCP server is read-only. Use dryRun to preview, and ask the user to start it with `knobs mcp --allow-write` to make changes."]], true)
        }
        switch name {
        case "list_settings":
            let category = args["category"] as? String
            let changedOnly = args["changedOnly"] as? Bool ?? false
            let live = CLI.liveStates()
            let rows = catalog.filter { category == nil || $0.category.rawValue == category }
                .map { CLI.record($0, live: live) }
                .filter { !changedOnly || $0["customized"] as? Bool == true }
            return (["settings": rows, "count": rows.count], false)
        case "describe_setting":
            guard let id = args["id"] as? String, let s = catalogByID[id] else {
                return (["ok": false, "errors": [L("unknown setting \"\(args["id"] ?? "")\" (see list_settings)", "不认识的设置“\(args["id"] ?? "")”(用 list_settings 查看)")]], true)
            }
            return (CLI.record(s, live: CLI.liveStates()), false)
        case "get_status":
            return (CLI.statusJSON(), false)
        case "verify_catalog":
            let r = Verify.run()
            var short = r
            short["settings"] = (r["settings"] as? [[String: Any]] ?? []).filter { $0["result"] as? String == "mismatch" }
            return (short, false)
        case "list_snapshots":
            return (["snapshots": Profile.backups().map { ["path": tildePath($0), "before": Profile.reason(ofSnapshot: $0)] }], false)
        case "set_settings":
            guard let changes = args["changes"] as? [String: Any], !changes.isEmpty else { return (["ok": false, "errors": ["changes must be an object of id: value"]], true) }
            let requests = changes.keys.sorted().map { Changes.Request(id: $0, value: Value(any: changes[$0]) ?? .string("")) }
            var out = Changes.run(requests, dryRun: dryRun, reason: "agent set " + changes.keys.sorted().joined(separator: ", "))
            if !dryRun { Changes.confirmLive(&out) }
            return (out.json, !out.ok)
        case "reset_settings":
            guard let ids = args["ids"] as? [String], !ids.isEmpty else { return (["ok": false, "errors": ["ids must be a non-empty list"]], true) }
            var out = Changes.run(ids.map { Changes.Request(id: $0, value: nil) }, dryRun: dryRun, reason: "agent reset " + ids.joined(separator: ", "))
            if !dryRun { Changes.confirmLive(&out) }
            return (out.json, !out.ok)
        case "apply_profile":
            guard let source = args["profile"] as? String else { return (["ok": false, "errors": ["profile is required"]], true) }
            switch CLI.loadProfile(source) {
            case .failure(let e): return (["ok": false, "errors": [e.description]], true)
            case .success(let text):
                do {
                    let report = try Profile.apply(text: text, dryRun: dryRun, reason: "agent apply \(source)")
                    if !dryRun { CLI.notifyApp() }
                    return (report.json(dryRun: dryRun), !report.problems.isEmpty)
                } catch { return (["ok": false, "errors": ["\(error)"]], true) }
            }
        case "undo":
            let r = Changes.undo()
            return (r.json, r.error != nil || !r.report.problems.isEmpty)
        default:
            return (["ok": false, "errors": ["unknown tool \(name)"]], true)
        }
    }

    // MARK: JSON-RPC over stdio

    private func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }

    private func handle(_ message: [String: Any]) {
        let id = message["id"]
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        func reply(_ result: [String: Any]) { if let id { send(["jsonrpc": "2.0", "id": id, "result": result]) } }
        func error(_ code: Int, _ text: String) { if let id { send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]]) } }

        switch method {
        case "initialize":
            reply(["protocolVersion": params["protocolVersion"] as? String ?? Self.protocolVersion,
                   "capabilities": ["tools": ["listChanged": false]],
                   "serverInfo": ["name": "knobs", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"],
                   "instructions": instructions])
        case "ping":
            reply([:])
        case "tools/list":
            reply(["tools": toolList()])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            let (result, isError) = call(name, args)
            reply(["content": [["type": "text", "text": jsonText(result)]], "structuredContent": result, "isError": isError])
        default:
            if method.hasPrefix("notifications/") { return }
            error(-32601, "method not found: \(method)")
        }
    }

    func run() -> Int32 {
        FileHandle.standardError.write(Data("knobs mcp: \(allowWrite ? "writes enabled" : "read-only (start with --allow-write to change settings)")\n".utf8))
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]])
                continue
            }
            if let batch = obj as? [[String: Any]] { batch.forEach(handle) }
            else if let message = obj as? [String: Any] { handle(message) }
        }
        return 0
    }
}
