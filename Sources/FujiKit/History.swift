import Foundation

/// What each slot of a camera held, and when: `history/<model>-<serial>.json` in the library. Every write moves the
/// slot's current contents into `past` (so "Put back" can restore them), and every connect records what the camera
/// holds now (a change made on the camera itself shows up as a new entry). Shared by the app, `fuji mcp` and the CLI.
public struct SlotRecord: Codable, Equatable, Sendable, Identifiable {
    public var slot: String              // "C3", "FS1"
    public var name: String
    public var settings: RecipeSettings
    public var from: String?             // ISO date it was first seen there; nil = before we started watching
    public var to: String?               // nil while it's still on the camera
    public var how: String?              // "written", "on the camera", "put back"
    public var id: String { "\(slot)|\(from ?? "")|\(to ?? "now")" }

    public init(slot: String, name: String, settings: RecipeSettings, from: String?, to: String? = nil, how: String? = nil) {
        self.slot = slot; self.name = name; self.settings = settings; self.from = from; self.to = to; self.how = how
    }
}

public struct SlotHistoryFile: Codable, Sendable {
    public var camera: String
    public var current: [String: SlotRecord] = [:]
    public var past: [SlotRecord] = []
}

public extension Library {
    private var historyDir: URL { root.appendingPathComponent("history") }

    private func historyURL(_ camera: DeviceInfo) -> URL {
        let key = Recipe.slugify("\(camera.model) \(camera.serial.suffix(8))")
        return historyDir.appendingPathComponent("\(key.isEmpty ? "camera" : key).json")
    }

    func slotHistory(_ camera: DeviceInfo) -> SlotHistoryFile {
        (try? JSONDecoder().decode(SlotHistoryFile.self, from: Data(contentsOf: historyURL(camera))))
            ?? SlotHistoryFile(camera: camera.model)
    }

    private func save(_ h: SlotHistoryFile, for camera: DeviceInfo) throws {
        try FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        var data = try Library.encoder.encode(h); data.append(0x0A)
        try data.write(to: historyURL(camera), options: .atomic)
    }

    /// On connect: what each slot holds now. A slot that changed since last time (on the camera, or by another tool)
    /// gets its old contents moved to `past`.
    func observe(_ camera: DeviceInfo, slots: [(slot: String, name: String, settings: RecipeSettings)]) {
        var h = slotHistory(camera)
        let now = Date().isoStamp
        var changed = false
        for s in slots {
            if let cur = h.current[s.slot], cur.settings == s.settings, cur.name == s.name { continue }
            if var old = h.current[s.slot] { old.to = now; h.past.insert(old, at: 0) }
            h.current[s.slot] = SlotRecord(slot: s.slot, name: s.name, settings: s.settings,
                                           from: h.current[s.slot] == nil ? nil : now, how: "on the camera")
            changed = true
        }
        if changed { try? save(h, for: camera) }
    }

    /// After a successful write: the old contents go to `past`, the new ones become current.
    func recordWrite(_ camera: DeviceInfo, slot: String, name: String, settings: RecipeSettings, how: String = "written") {
        var h = slotHistory(camera)
        let now = Date().isoStamp
        if var old = h.current[slot], old.settings != settings || old.name != name {
            old.to = now; h.past.insert(old, at: 0)
        }
        h.current[slot] = SlotRecord(slot: slot, name: name, settings: settings, from: now, how: how)
        try? save(h, for: camera)
    }

    /// One slot's story: what's there now, then what was there before, newest first.
    func history(_ camera: DeviceInfo, slot: String) -> [SlotRecord] {
        let h = slotHistory(camera)
        return [h.current[slot]].compactMap { $0 } + h.past.filter { $0.slot == slot }
    }
}
