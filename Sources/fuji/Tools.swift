import FujiKit
import Foundation

typealias JSON = [String: Any]

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// Encodable → plain JSON objects for the MCP reply.
func plain<T: Encodable>(_ value: T) -> Any {
    let data = (try? Library.encoder.encode(value)) ?? Data("null".utf8)
    return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull()
}

func decode<T: Decodable>(_ type: T.Type, from object: Any?) throws -> T {
    guard let object, JSONSerialization.isValidJSONObject(object) || object is String || object is NSNumber else { throw ToolError("missing value") }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
    return try JSONDecoder().decode(T.self, from: data)
}

/// A prepared camera write, applied only after the user approves its preview.
struct Plan {
    struct Write { var slot: Int; var settings: RecipeSettings; var name: String; var label: String; var exactName = false }
    var id: String
    var created: Date
    var cameraSerial: String
    var writes: [Write]
    var preview: [String]
}

final class Tools: @unchecked Sendable {
    let library = Library()
    var plans: [String: Plan] = [:]

    // MARK: Definitions

    static let recipeArg: JSON = ["type": "string", "description": "Recipe slug or name (fuji_recipes lists them)"]
    static let settingsSchema: JSON = ["type": "object", "description": "Recipe settings, keys as in fuji_guide: film, grain_roughness, grain_size, color_chrome, color_chrome_fx_blue, wb, wb_kelvin, wb_red, wb_blue, dynamic_range, d_range_priority, highlight, shadow, color, mono_warm_cool, mono_magenta_green, sharpness, high_iso_nr, clarity"]
    static let ro: JSON = ["readOnlyHint": true]

    let definitions: [JSON] = [
        ["name": "fuji_camera", "description": "Is a Fujifilm camera connected over USB? Model, firmware, USB mode (must be USB RAW CONV./BACKUP RESTORE to read or write slots), number of custom slots, and what to do if it isn't found.",
         "inputSchema": ["type": "object", "properties": [:]], "annotations": ro],
        ["name": "fuji_doctor", "description": "Why can't the camera be read? Checks the connection one step at a time (USB → macOS camera → session → USB mode → slots, plus photo apps that grab cameras) and returns each step with what it saw and the fix for the first one that fails. Read-only. Use it whenever fuji_camera or fuji_slots fails, and show the user the fix in their words.",
         "inputSchema": ["type": "object", "properties": [:]], "annotations": ro],
        ["name": "fuji_slots", "description": "Read every custom slot (C1–C7, C1–C4 on X-S20 / X-M5) from the connected camera: name, settings, a one-line summary, and which library recipe it matches. On an X-E5 also the film simulation dial's FS1–FS3 (read only, from the camera's settings file; WB shift and mono toning there are unverified). Reading changes nothing.",
         "inputSchema": ["type": "object", "properties": [:]], "annotations": ro],
        ["name": "fuji_recipes", "description": "List the recipe library (~/Documents/FujiRecipes): slug, name, status (favorite, mine = shot with it, tried, to-try, rejected), film, one-line summary, shots, source.",
         "inputSchema": ["type": "object", "properties": ["status": ["type": "string", "enum": Values.status], "film": ["type": "string"], "query": ["type": "string", "description": "Text in the name, slug, creator or notes"]]], "annotations": ro],
        ["name": "fuji_recipe", "description": "One recipe in full: settings, the text to dial it in by hand, shooting advice (ISO, exposure — not stored in a slot), source and credit, sample photos.",
         "inputSchema": ["type": "object", "properties": ["recipe": recipeArg], "required": ["recipe"]], "annotations": ro],
        ["name": "fuji_compare", "description": "Field-by-field differences between two recipes or slots. Each side is a recipe slug/name or a slot like \"C3\" (read from the camera).",
         "inputSchema": ["type": "object", "properties": ["a": ["type": "string"], "b": ["type": "string"]], "required": ["a", "b"]], "annotations": ro],
        ["name": "fuji_kits", "description": "Kits: named sets of recipes for the slots (\"Iceland\": C1 Green Acros, C2 Strong Classic Neg, …), written in one go with fuji_plan_write.",
         "inputSchema": ["type": "object", "properties": [:]], "annotations": ro],
        ["name": "fuji_backups", "description": "Saved snapshots of the camera's slots (one is taken automatically before every write), newest first.",
         "inputSchema": ["type": "object", "properties": [:]], "annotations": ro],
        ["name": "fuji_guide", "description": "How recipes and slots work: every field and its allowed values, what a slot can't store (ISO, exposure), camera rules (DR200/400 need higher ISO, D-Range Priority locks DR and tone, mono films have no Color), supported bodies, safety and the warranty note.",
         "inputSchema": ["type": "object", "properties": [:]], "annotations": ro],
        ["name": "fuji_save_recipe", "description": "Add or update a recipe in the library (for one read from a reel, a screenshot, a website, or typed in). Checks every value against what the camera accepts and refuses a duplicate of an existing recipe's settings (pass allowDuplicate to keep both). Credit the creator in source.",
         "inputSchema": ["type": "object", "properties": [
            "slug": ["type": "string", "description": "Optional; made from the name"], "name": ["type": "string"],
            "status": ["type": "string", "enum": Values.status], "settings": settingsSchema,
            "shooting": ["type": "object", "description": "{iso, exposure_compensation, notes}: advice that a slot can't store"],
            "source": ["type": "object", "description": "{kind: reel|website|exif|camera|manual, url, creator, credit, transcript}"],
            "uncertain": ["type": "array", "items": ["type": "string"], "description": "Fields read with doubt, e.g. settings.wb_blue"],
            "notes": ["type": "string"], "allowDuplicate": ["type": "boolean"]], "required": ["name", "settings"]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_set_status", "description": "Mark a recipe favorite, tried, to-try, rejected or mine, optionally adding a note (\"too green in shade\").",
         "inputSchema": ["type": "object", "properties": ["recipe": recipeArg, "status": ["type": "string", "enum": Values.status], "note": ["type": "string"]], "required": ["recipe", "status"]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_save_kit", "description": "Save a kit: a name and recipes for slots, e.g. {name: \"Iceland\", slots: {C1: \"green-acros\", C2: \"strong-classic-neg\"}}.",
         "inputSchema": ["type": "object", "properties": ["name": ["type": "string"], "slots": ["type": "object"], "notes": ["type": "string"]], "required": ["name", "slots"]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_save_slot", "description": "Save what a camera slot holds as a library recipe (to keep a recipe someone set up by hand).",
         "inputSchema": ["type": "object", "properties": ["slot": ["type": "string", "description": "C1…C7"], "name": ["type": "string"], "status": ["type": "string", "enum": Values.status]], "required": ["slot"]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_import_photos", "description": "Find the recipes the user actually shot with from their Fujifilm JPEGs' EXIF (every Fuji JPEG stores its recipe), grouping identical settings. Recipes already in the library get shot counts and sample photos; new ones are added as status mine with a placeholder name. dryRun lists without writing. Needs exiftool.",
         "inputSchema": ["type": "object", "properties": ["folders": ["type": "array", "items": ["type": "string"]], "spotlight": ["type": "boolean", "description": "Every Fujifilm JPEG Spotlight knows (default when no folders)"], "min": ["type": "integer", "description": "Ignore recipes with fewer shots (default 3)"], "dryRun": ["type": "boolean"]]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_backup", "description": "Save a snapshot of every slot on the connected camera to the library's backups folder. Changes nothing on the camera.",
         "inputSchema": ["type": "object", "properties": ["reason": ["type": "string"]]], "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_plan_write", "description": """
         Prepare writing recipes to the camera's custom slots WITHOUT writing; returns a plan id and a preview of every change (slot, old → new, field by field) to show the user. Operations:
         • {slot: "C3", recipe: "<slug or name>", name?: "<slot name, ≤25 ASCII>"} — a library recipe into a slot
         • {slot: "C3", settings: {…}, name: "…"} — settings not in the library
         • {kit: "<kit>"} — every slot of a kit
         • {restore: "<backup file or latest>", slots?: ["C1", "C2"]} — put slots back from a backup
         Then call fuji_apply_write only after the user approves.
         """,
         "inputSchema": ["type": "object", "properties": ["operations": ["type": "array", "items": ["type": "object"]]], "required": ["operations"]],
         "annotations": ro],
        ["name": "fuji_apply_write", "description": "Write a plan from fuji_plan_write to the camera after the user approved its preview. Saves a backup of every slot first, writes only the changed values in the camera's order, reads each slot back and reports anything the camera refused or stored differently.",
         "inputSchema": ["type": "object", "properties": ["planId": ["type": "string"]], "required": ["planId"]],
         "annotations": ["readOnlyHint": false, "destructiveHint": true]],
    ]

    // MARK: Calls

    func call(_ name: String, _ a: JSON) async throws -> Any {
        switch name {
        case "fuji_camera": return try await camera()
        case "fuji_doctor": return Doctor.json(await Doctor.run())
        case "fuji_slots": return try await slots()
        case "fuji_recipes": return try recipes(a)
        case "fuji_recipe": return try recipe(a)
        case "fuji_compare": return try await compare(a)
        case "fuji_kits": return plain(try library.kits())
        case "fuji_backups":
            return try library.backups().map { url -> JSON in
                let s = try library.backup(url.lastPathComponent)
                return ["file": url.lastPathComponent, "date": s.date, "reason": s.reason, "camera": s.camera.model,
                        "slots": s.banks.map { "\($0.slot) \($0.name.isEmpty ? "—" : $0.name): \($0.settings.film)" }]
            }
        case "fuji_guide": return Guide.text
        case "fuji_save_recipe": return try saveRecipe(a)
        case "fuji_set_status":
            let r = try library.setStatus(str(a, "recipe"), status: str(a, "status"), note: a["note"] as? String)
            return ["saved": r.slug, "status": r.status]
        case "fuji_save_kit":
            let slots = (a["slots"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            let k = try library.save(Kit(slug: "", name: str(a, "name"), slots: slots, notes: a["notes"] as? String))
            return plain(k)
        case "fuji_save_slot": return try await saveSlot(a)
        case "fuji_import_photos": return try importPhotos(a)
        case "fuji_backup":
            let url = try await backup(reason: a["reason"] as? String ?? "Asked for")
            return ["backup": url.path]
        case "fuji_plan_write": return try await planWrite(a["operations"] as? [JSON] ?? [])
        case "fuji_apply_write": return try await applyWrite(str(a, "planId"))
        default: throw ToolError("Unknown tool \(name).")
        }
    }

    func str(_ a: JSON, _ key: String) throws -> String {
        guard let v = a[key] as? String, !v.isEmpty else { throw ToolError("\(key) is required") }
        return v
    }

    func camera() async throws -> Any {
        guard let cam = await Cameras.shared.current() else {
            return ["connected": false, "advice": Cameras.shared.noCameraAdvice()] as JSON
        }
        let info = try await cam.deviceInfo()
        let mode = try await cam.usbMode()
        var out: JSON = ["connected": true, "model": info.model, "firmware": info.firmware, "usbMode": mode.label,
                         "canReadWriteSlots": mode.canWriteSlots, "simulated": Cameras.shared.simulate]
        if mode.canWriteSlots {
            out["slots"] = try await cam.bankCount()
            out["note"] = "The camera's menu is locked while it's connected in this mode. FS1–FS3 on a film simulation dial can't be written over USB; the dial overrides a slot's film simulation unless it's set to C."
        } else {
            out["advice"] = "The camera is in \(mode.label) mode, where its custom slots can't be reached. \(USBMode.howToSet)"
        }
        return out
    }

    func slots() async throws -> Any {
        let cam = try await Cameras.shared.require()
        let banks = try await cam.readAll()
        var out = banks.map { b -> JSON in
            var o: JSON = ["slot": b.slot, "name": b.name, "summary": b.settings.summary, "settings": plain(b.settings)]
            if let r = library.match(b.settings) { o["recipe"] = r.slug; o["recipeName"] = r.name }
            return o
        }
        // Film simulation dial (X-E5): FS1–FS3 live only in the camera's settings file. Read-only.
        let info = try await cam.deviceInfo()
        if SettingsFile.layout(model: info.model) != nil, let file = try? await cam.downloadSettingsBackup(),
           let dial = SettingsFile.dialSlots(file, model: info.model) {
            out += dial.map { d -> JSON in
                var o: JSON = ["slot": d.slot, "readOnly": true, "summary": d.settings.summary, "settings": plain(d.settings),
                               "unverified": d.unverified]
                if let r = library.match(d.settings) { o["recipe"] = r.slug; o["recipeName"] = r.name }
                return o
            }
        }
        return out
    }

    func recipes(_ a: JSON) throws -> Any {
        var all = try library.recipes()
        if let s = a["status"] as? String { all = all.filter { $0.status == s } }
        if let f = (a["film"] as? String)?.lowercased() { all = all.filter { $0.settings.film.lowercased().contains(f) } }
        if let q = (a["query"] as? String)?.lowercased(), !q.isEmpty {
            all = all.filter { [$0.name, $0.slug, $0.source?.creator ?? "", $0.notes ?? ""].joined(separator: " ").lowercased().contains(q) }
        }
        return ["library": library.root.path, "count": all.count,
                "recipes": all.map { r -> JSON in
                    ["slug": r.slug, "name": r.name, "status": r.status, "film": r.settings.film, "summary": r.settings.summary,
                     "shots": r.shots ?? 0, "source": r.source?.creator ?? r.source?.kind ?? ""]
                }] as JSON
    }

    func recipe(_ a: JSON) throws -> Any {
        let r = try library.recipe(str(a, "recipe"))
        var o = plain(r) as? JSON ?? [:]
        o["text"] = r.settings.text
        o["summary"] = r.settings.summary
        return o
    }

    func settings(for side: String) async throws -> (String, RecipeSettings) {
        if side.uppercased().range(of: #"^C[1-7]$"#, options: .regularExpression) != nil {
            let cam = try await Cameras.shared.require()
            let b = try await cam.readBank(Int(side.dropFirst())!)
            return ("\(b.slot) \(b.name)", b.settings)
        }
        let r = try library.recipe(side)
        return (r.name, r.settings)
    }

    func compare(_ a: JSON) async throws -> Any {
        let (na, sa) = try await settings(for: str(a, "a"))
        let (nb, sb) = try await settings(for: str(a, "b"))
        let d = sa.differences(to: sb)
        return ["a": na, "b": nb, "same": d.isEmpty, "differences": d] as JSON
    }

    func saveRecipe(_ a: JSON) throws -> Any {
        var obj = a
        obj["slug"] = (a["slug"] as? String) ?? ""
        obj["status"] = (a["status"] as? String) ?? "to-try"
        obj.removeValue(forKey: "allowDuplicate")
        var r = try decode(Recipe.self, from: obj)
        if r.source?.dateAdded == nil, r.source != nil { r.source?.dateAdded = Date().day }
        if r.source == nil { r.source = .init(kind: "manual", dateAdded: Date().day) }
        let saved = try library.save(r, allowDuplicate: a["allowDuplicate"] as? Bool ?? false)
        return ["saved": saved.slug, "file": library.root.appendingPathComponent("recipes/\(saved.slug).json").path, "summary": saved.settings.summary] as JSON
    }

    func saveSlot(_ a: JSON) async throws -> Any {
        let slot = try str(a, "slot").uppercased()
        guard slot.range(of: #"^C[1-7]$"#, options: .regularExpression) != nil else { throw ToolError("slot must be C1…C7") }
        let cam = try await Cameras.shared.require()
        let b = try await cam.readBank(Int(slot.dropFirst())!)
        if let twin = library.match(b.settings) { return ["alreadyInLibrary": twin.slug, "name": twin.name] as JSON }
        let name = (a["name"] as? String) ?? (b.name.isEmpty ? "\(slot) \(b.settings.film)" : b.name.capitalized)
        var r = Recipe(slug: "", name: name, status: a["status"] as? String ?? "tried", settings: b.settings)
        let info = try await cam.deviceInfo()
        r.source = .init(kind: "camera", dateAdded: Date().day)
        r.notes = "Read from \(slot) of the \(info.model)."
        let saved = try library.save(r)
        return ["saved": saved.slug, "summary": saved.settings.summary] as JSON
    }

    func importPhotos(_ a: JSON) throws -> Any {
        let folders = a["folders"] as? [String] ?? []
        let files = folders.isEmpty ? ExifImport.spotlightFiles() : ExifImport.files(in: folders)
        let groups = try ExifImport.groups(files: files)
        let min = a["min"] as? Int ?? 3
        let found = groups.filter { $0.files.count >= min }.map { g -> JSON in
            var o: JSON = ["shots": g.files.count, "cameras": Array(g.cameras).sorted(), "summary": g.settings.summary,
                           "from": g.dates.min() ?? "", "to": g.dates.max() ?? "", "example": g.files.first ?? ""]
            if let r = library.match(g.settings) { o["recipe"] = r.slug }
            return o
        }
        if a["dryRun"] as? Bool == true { return ["photos": files.count, "recipes": found] as JSON }
        let report = try ExifImport.importGroups(groups, into: library, min: min)
        return ["photos": files.count, "recipes": found, "library": report] as JSON
    }

    @discardableResult
    func backup(reason: String) async throws -> URL {
        let cam = try await Cameras.shared.require()
        let info = try await cam.deviceInfo()
        let banks = try await cam.readAll()
        return try library.saveBackup(Snapshot(date: Date().isoStamp, reason: reason, camera: info, banks: banks))
    }

    func planWrite(_ ops: [JSON]) async throws -> Any {
        guard !ops.isEmpty else { throw ToolError("operations is empty") }
        let cam = try await Cameras.shared.require()
        let info = try await cam.deviceInfo()
        let mode = try await cam.usbMode()
        guard mode.canWriteSlots else { throw ToolError("The camera is in \(mode.label). Set it to \(USBMode.rawConvBackupRestore.label) and plug it in again.") }
        let count = try await cam.bankCount()
        var writes: [Plan.Write] = []
        func slotIndex(_ s: String) throws -> Int {
            guard let n = Int(s.uppercased().dropFirst()), s.uppercased().hasPrefix("C"), (1...count).contains(n) else {
                throw ToolError("\(s) isn't a slot on the \(info.model) (C1…C\(count)).")
            }
            return n
        }
        for op in ops {
            if let kitName = op["kit"] as? String {
                let kit = try library.kit(kitName)
                for (slot, slug) in kit.slots.sorted(by: { $0.key < $1.key }) {
                    let r = try library.recipe(slug)
                    writes.append(.init(slot: try slotIndex(slot), settings: r.settings, name: r.name.uppercased(), label: r.name))
                }
            } else if let backupName = op["restore"] as? String {
                let snap = try library.backup(backupName)
                let only = (op["slots"] as? [String])?.map { $0.uppercased() }
                for b in snap.banks where only?.contains(b.slot) ?? true {
                    writes.append(.init(slot: try slotIndex(b.slot), settings: b.settings, name: b.name, label: "backup \(snap.date.prefix(16))", exactName: true))
                }
            } else if let slot = op["slot"] as? String {
                let index = try slotIndex(slot)
                if let q = op["recipe"] as? String {
                    let r = try library.recipe(q)
                    writes.append(.init(slot: index, settings: r.settings, name: (op["name"] as? String) ?? r.name.uppercased(), label: r.name))
                } else if let s = op["settings"] {
                    let settings = try decode(RecipeSettings.self, from: s)
                    let probe = Recipe(slug: "probe", name: "probe", settings: settings)
                    let bad = probe.problems
                    guard bad.isEmpty else { throw ToolError("The camera can't take \(bad.joined(separator: ", ")).") }
                    writes.append(.init(slot: index, settings: settings, name: (op["name"] as? String) ?? "", label: "custom settings"))
                } else { throw ToolError("\(slot): give a recipe or settings") }
            } else { throw ToolError("Each operation needs slot, kit or restore.") }
        }
        var preview: [String] = []
        for w in writes {
            let current = try await cam.readBank(w.slot)
            let name = PTPString.bankName(w.name.isEmpty && !w.exactName ? current.name : w.name)
            var diffs = current.settings.differences(to: w.settings)
            if name != current.name { diffs.insert("name: \(current.name.isEmpty ? "—" : current.name) → \(name)", at: 0) }
            preview.append("C\(w.slot) \(current.name.isEmpty ? "(unnamed)" : current.name) → \(w.label)" +
                           (diffs.isEmpty ? ": already the same, nothing to write" : "\n    " + diffs.joined(separator: "\n    ")))
        }
        preview.append("A backup of all \(count) slots is saved first. Each slot is read back after writing.")
        let plan = Plan(id: String(UUID().uuidString.prefix(8)).lowercased(), created: Date(), cameraSerial: info.serial,
                        writes: writes, preview: preview)
        plans[plan.id] = plan
        return ["planId": plan.id, "camera": info.model, "preview": preview,
                "next": "Show this preview to the user. Call fuji_apply_write only after they approve."] as JSON
    }

    func applyWrite(_ id: String) async throws -> Any {
        guard let plan = plans[id] else { throw ToolError("No plan \(id) (plans last until the server restarts). Prepare it again with fuji_plan_write.") }
        guard Date().timeIntervalSince(plan.created) < 1800 else { plans[id] = nil; throw ToolError("Plan \(id) is older than 30 minutes; prepare it again so the preview matches the camera.") }
        let cam = try await Cameras.shared.require()
        let info = try await cam.deviceInfo()
        guard info.serial == plan.cameraSerial else { throw ToolError("A different camera is connected than when the plan was made. Prepare it again.") }
        let backupURL = try await backup(reason: "Before writing \(plan.writes.map { "C\($0.slot)" }.joined(separator: ", "))")
        var reports: [Any] = []
        for w in plan.writes {
            let report = try await cam.writeBank(w.slot, settings: w.settings, name: w.name.isEmpty && !w.exactName ? nil : w.name)
            var o = plain(report) as? JSON ?? [:]
            o["ok"] = report.ok
            reports.append(o)
        }
        plans[id] = nil
        return ["backup": backupURL.path, "slots": reports,
                "note": "To shoot with a slot: unplug, turn the film simulation dial to C, press Q, and turn the rear command dial to the slot (SELECT CUSTOM SETTING). On a named film or FS1–FS3 the dial overrides the slot's film simulation."] as JSON
    }
}
