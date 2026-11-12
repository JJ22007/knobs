// Changing settings one at a time, the way the command line, the window and the MCP server
// all do it: validate, save a snapshot, write, read back, and report in one shape.

import Foundation

enum Changes {
    /// One requested change. `value == nil` hands the setting back to macOS (reset).
    struct Request {
        let id: String
        let value: Value?
    }

    struct Outcome {
        var items: [[String: Any]] = []
        var errors: [String] = []
        var snapshot: String?
        var dryRun = false
        /// Live features that were switched; the caller decides whether to wait for the app.
        var liveIDs: [String] = []

        var ok: Bool { errors.isEmpty }

        var json: [String: Any] {
            var obj: [String: Any] = ["ok": ok, "dryRun": dryRun, "changes": items, "errors": errors,
                                      "snapshot": snapshot.map(tildePath) ?? NSNull()]
            if snapshot != nil { obj["undo"] = "knobs undo" }
            return obj
        }
    }

    /// What a setting looks like to a reader: the value, or the macOS default when it was never set.
    static func shownValue(_ s: Setting, _ v: Value?) -> Any { (v ?? s.systemDefault)?.any ?? NSNull() }

    /// Validates every request first, saves one snapshot if anything will really change, then writes.
    /// `reason` is stored in the snapshot so `knobs undo --list` can say what it undoes.
    static func run(_ requests: [Request], dryRun: Bool, reason: String) -> Outcome {
        var out = Outcome()
        out.dryRun = dryRun

        // 1. Check everything before touching anything.
        var plan: [(Setting, Value?)] = []
        for r in requests {
            guard let s = catalogByID[r.id] else {
                out.errors.append(L("unknown setting \"\(r.id)\" (see `knobs list`)", "不认识的设置“\(r.id)”(用 `knobs list` 查看)")); continue
            }
            if let v = r.value {
                do { plan.append((s, try Engine.validate(s, v))) } catch { out.errors.append("\(error)") }
            } else {
                plan.append((s, nil))
            }
        }

        // All or nothing: a typo in one id must not leave the other half of the batch applied.
        if !out.errors.isEmpty, !dryRun {
            out.errors.append(L("nothing was changed", "没有做任何修改"))
            return out
        }

        func willChange(_ s: Setting, _ wanted: Value?) -> Bool {
            let now = Engine.current(s)
            if case .live = s.backing { return (now?.asBool ?? false) != (wanted?.asBool ?? false) }
            if let wanted {
                if s.id == "screenshots.location" { return now?.asString.map(expandTilde) != wanted.asString.map(expandTilde) }
                return now != wanted
            }
            return now != nil
        }

        // 2. One snapshot for the whole batch, only if something will actually change.
        if !dryRun, plan.contains(where: { willChange($0.0, $0.1) }) {
            out.snapshot = Profile.saveSnapshot(reason: reason)
            if out.snapshot == nil {
                out.errors.append(L("could not save a snapshot in \(Profile.backupDirectory), so nothing was changed",
                                    "无法在 \(Profile.backupDirectory) 保存快照,所以没有做任何修改"))
                return out
            }
        }

        // 3. Write and read back.
        var restart = Set<String>()
        for (s, wanted) in plan {
            let before = Engine.current(s)
            var item: [String: Any] = [
                "id": s.id, "before": shownValue(s, before), "takesEffect": s.timing.rawValue,
                "takesEffectText": s.timing.label, "changed": willChange(s, wanted),
            ]
            if wanted == nil { item["reset"] = true }
            if dryRun {
                item["after"] = shownValue(s, wanted)
                out.items.append(item)
                continue
            }
            do {
                let r: Set<String>
                if let wanted { r = try Engine.set(s, wanted) } else { r = Engine.reset(s) }
                restart.formUnion(r)
                let after = Engine.current(s)
                item["after"] = shownValue(s, after)
                if !r.isEmpty { item["restarts"] = r.sorted() }
                if case .live = s.backing {
                    out.liveIDs.append(s.id)
                    item["verified"] = NSNull()   // filled in once the app reports back
                } else {
                    // Engine.set already throws when the read-back differs; a reset must leave no key.
                    item["verified"] = wanted == nil ? after == nil : true
                }
            } catch {
                item["error"] = "\(error)"
                out.errors.append("\(error)")
            }
            out.items.append(item)
        }
        if !dryRun {
            Prefs.restart(restart)
            CLI.notifyApp()
        }
        return out
    }

    /// For live features: start the app if needed, wait for it to act, and mark each item verified or not.
    static func confirmLive(_ out: inout Outcome) {
        guard !out.liveIDs.isEmpty else { return }
        let states = CLI.waitForLive(out.liveIDs)
        for i in out.items.indices {
            guard let id = out.items[i]["id"] as? String, out.liveIDs.contains(id), let s = catalogByID[id] else { continue }
            let wanted = Engine.current(s) == .bool(true)
            guard let state = states?[id] as? [String: Any] else {
                out.items[i]["verified"] = false
                out.errors.append(L("\(id): the Knobs app did not answer", "\(id):Knobs 应用没有响应"))
                continue
            }
            let active = state["active"] as? Bool ?? false
            out.items[i]["active"] = active
            out.items[i]["verified"] = active == wanted
            if let note = state["note"] as? String, !note.isEmpty { out.items[i]["note"] = note }
            if active != wanted {
                let note = state["note"] as? String ?? ""
                out.errors.append(L("\(id) is set to \(wanted ? "on" : "off") but is \(active ? "still active" : "not active yet")\(note.isEmpty ? "" : ": " + note)",
                                    "\(id) 已设为 \(wanted ? "on" : "off"),但\(active ? "仍在生效" : "还没有生效")\(note.isEmpty ? "" : ":" + note)"))
            }
        }
    }

    // MARK: Undo

    struct UndoResult {
        var report = Profile.Report()
        var from: String?
        var reason = ""
        var error: String?

        var json: [String: Any] {
            if let error { return ["ok": false, "errors": [error]] }
            var obj = report.json(dryRun: false)
            obj["restoredFrom"] = from.map(tildePath) ?? NSNull()
            obj["undid"] = reason
            obj["remaining"] = Profile.backups().count
            return obj
        }
    }

    /// Puts back the newest snapshot and removes it, so the next undo goes one step further back.
    static func undo() -> UndoResult {
        var result = UndoResult()
        guard let latest = Profile.backups().first, let text = try? String(contentsOfFile: latest, encoding: .utf8) else {
            result.error = L("nothing to undo: no change has been made with Knobs yet", "没有可撤销的:还没有用 Knobs 改过设置")
            return result
        }
        result.from = latest
        result.reason = Profile.reason(ofSnapshot: latest)
        do {
            result.report = try Profile.apply(text: text, dryRun: false, snapshot: false)
            try? FileManager.default.removeItem(atPath: latest)
            CLI.notifyApp()
        } catch { result.error = "\(error)" }
        return result
    }
}

/// Paths in output use ~ so agent transcripts and logs do not carry the account name.
func tildePath(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

/// JSON for printing: sorted keys, slashes left alone.
func jsonText(_ obj: Any) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    return String(decoding: data, as: UTF8.self)
}
