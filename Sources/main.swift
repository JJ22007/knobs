// Entry point.
//   Knobs                      run the app (menu bar item and settings window)
//   Knobs --background         run without opening the window
//   Knobs --selftest           check the catalog, value handling and profiles
//   Knobs list | set | ...     command line interface, see CLI.swift

import AppKit

func selfTest() -> Int32 {
    var fails = 0
    func expect(_ name: String, _ ok: Bool, _ detail: String = "") {
        if !ok { fails += 1 }
        print("\(ok ? "ok  " : "FAIL") \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    expect("catalog ids are unique", Set(catalog.map { $0.id }).count == catalog.count)
    expect("catalog ids look like group.name", catalog.allSatisfy { $0.id.split(separator: ".").count == 2 })
    for s in catalog {
        if let d = s.systemDefault {
            expect("default of \(s.id) is a valid value", (try? Engine.validate(s, d)) != nil, "\(d)")
        }
        if case .live(let feature) = s.backing { expect("live id \(s.id) is known", !feature.rawValue.isEmpty) }
    }

    func setting(_ id: String) -> Setting { catalogByID[id]! }
    expect("toggle accepts on/off/true/0", ["on", "off", "true", "0"].allSatisfy { (try? Engine.validate(setting("dock.autohide"), .string($0))) != nil })
    expect("toggle rejects nonsense", (try? Engine.validate(setting("dock.autohide"), .string("maybe"))) == nil)
    expect("number from text", (try? Engine.validate(setting("dock.autohideDelay"), .string("0.5"))) == .double(0.5))
    expect("whole number is rounded to an int", (try? Engine.validate(setting("dock.size"), .double(48))) == .int(48))
    expect("number out of range is rejected", (try? Engine.validate(setting("dock.size"), .int(4000))) == nil)
    expect("choice accepts a listed value", (try? Engine.validate(setting("dock.position"), .string("left"))) == .string("left"))
    expect("choice rejects an unlisted value", (try? Engine.validate(setting("dock.position"), .string("top"))) == nil)

    expect("value: JSON true is a bool, 1 is an int, 0.5 a double",
           Value(any: true as NSNumber) == .bool(true) && Value(any: 1 as NSNumber) == .int(1) && Value(any: 0.5 as NSNumber) == .double(0.5))

    let k = KeyCombo.parse("ctrl+left")
    expect("shortcut ctrl+left", k?.code == 123 && k?.flags == .maskControl)
    expect("shortcut Ctrl+Alt+1", KeyCombo.parse("Ctrl+Alt+1")?.flags == [.maskControl, .maskAlternate])
    expect("shortcut without a modifier is rejected", KeyCombo.parse("left") == nil)
    expect("nonsense shortcut is rejected", KeyCombo.parse("ctrl+banana") == nil)
    expect("default shortcuts parse", Config.defaultShortcuts.values.allSatisfy { KeyCombo.parse($0) != nil })

    let c = Config(json: ["live": ["spaces.instant": true], "shortcuts": ["space1": "ctrl+1"]])
    expect("config: partial file keeps default shortcuts", c.live["spaces.instant"] == true && c.shortcuts["space1"] == "ctrl+1" && c.shortcuts["spaceLeft"] == "ctrl+left")
    expect("config: round trip", Config(json: c.json) == c)

    // Exporting this Mac and applying the result must be a no-op. Reads only; nothing is written.
    let report = try? Profile.apply(text: Profile.exportText(), dryRun: true)
    expect("profile: export then apply changes nothing", report?.changed.isEmpty == true && report?.problems.isEmpty == true,
           "\(report?.changed ?? []) \(report?.problems ?? [])")
    expect("profile: garbage is refused", (try? Profile.apply(text: "{}", dryRun: true)) == nil)
    let odd = try? Profile.apply(text: #"{"knobs":1,"settings":{"no.such":true,"dock.position":"top"},"files":{"~/.zshrc":"x"}}"#, dryRun: true)
    expect("profile: unknown id, bad value and unlisted file are skipped with a reason", odd?.problems.count == 3 && odd?.changed.isEmpty == true, "\(odd?.problems ?? [])")

    // A profile is shared, so it must never carry the account's home folder or name.
    let exported = Profile.exportText()
    expect("profile: no home folder or account name in an export",
           !exported.contains(NSHomeDirectory()) && !exported.contains("/Users/\(NSUserName())"))
    let sample = #"{"path": "\#(NSHomeDirectory())/Projects"}"#
    expect("profile: home folder becomes ~ and comes back", Profile.expandHome(Profile.shortenHome(sample)) == sample
           && Profile.shortenHome(sample) == #"{"path": "~/Projects"}"#)

    // A batch with one bad value writes nothing. Dry run, so this Mac is untouched either way.
    let mixed = Changes.run([.init(id: "dock.autohide", value: .string("on")), .init(id: "dock.position", value: .string("top"))], dryRun: true, reason: "test")
    expect("changes: a refused value is reported", !mixed.ok && mixed.errors.count == 1, "\(mixed.errors)")
    let unknown = Changes.run([.init(id: "no.such", value: .string("on"))], dryRun: true, reason: "test")
    expect("changes: an unknown id is refused", !unknown.ok)
    expect("paneful: a layout entry needs an app or a title", !Paneful.problems([["x": 0, "y": 0, "w": 1, "h": 1]]).isEmpty)
    expect("paneful: positions are fractions of the screen", !Paneful.problems([["app": "Keynote", "x": 0, "y": 0, "w": 2, "h": 1]]).isEmpty)
    expect("verify: a stored path is shown with ~", (Verify.shownForTest(.string(NSHomeDirectory() + "/Pictures")) as? String) == "~/Pictures")
    expect("scenes: present is listed with a title", Scenes.all().contains { $0.name == "present" && !$0.title.isEmpty && $0.title != "present" })
    expect("scenes: on only right after switching to it", Scenes.matches("present", newestReason: "scene present") && Scenes.matches("present", newestReason: "knobs apply present")
           && !Scenes.matches("present", newestReason: "knobs set dock.autohide on") && !Scenes.matches("present", newestReason: "knobs apply presenter"))
    expect("paneful: a good layout passes", Paneful.problems([["app": "Keynote", "x": 0, "y": 0, "w": 1, "h": 1]]).isEmpty)

    print(fails == 0 ? "all checks passed" : "\(fails) check(s) failed")
    return fails == 0 ? 0 : 1
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--selftest" { exit(selfTest()) }
if let first = arguments.first, CLI.commands.contains(first) { exit(CLI.run(arguments)) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
