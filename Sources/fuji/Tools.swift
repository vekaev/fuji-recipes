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
        ["name": "fuji_render", "description": "Studio: develop one of the owner's RAW files (.RAF, same camera model) with several recipes on the connected camera, as FUJIFILM X RAW Studio does, and return the JPEG paths (cached in the library's renders/ folder, so repeats are instant). Doesn't change any slot or setting. Recipes: slugs or names; default: favorites and to-try.",
         "inputSchema": ["type": "object", "properties": ["raw": ["type": "string", "description": "Path to a .RAF"],
                                                          "recipes": ["type": "array", "items": ["type": "string"]],
                                                          "full": ["type": "boolean", "description": "Full resolution (slower); default a 640-px preview"]],
                         "required": ["raw"]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_match_look", "description": "Match a look: from any reference photo (a Leica shot, a paid recipe's sample, a screenshot), propose a recipe that reproduces its tone, colour cast and saturation. Without raw: a first guess from the photo alone. With raw (one of the owner's .RAF files, same camera model, ideally a similar scene and light) and the camera connected: the camera develops the RAW with candidate recipes (budget renders, ~2 s each; film simulation first, then WB shift, tone, colour) and the three closest looks come back with a match % and the render's path. save: a name to keep the best as a to-try recipe. Doesn't change any slot or setting.",
         "inputSchema": ["type": "object", "properties": ["image": ["type": "string", "description": "Path to the reference photo"],
                                                          "raw": ["type": "string", "description": "Path to a .RAF to develop on the camera (optional)"],
                                                          "budget": ["type": "integer", "description": "Camera renders to spend, default 60"],
                                                          "save": ["type": "string", "description": "Name for the best result, saved as a to-try recipe"],
                                                          "evaluate": ["type": "boolean", "description": "Instead: report how accurate the first guess is on the library's (and reference sets') sample photos"],
                                                          "learn": ["type": "string", "description": "Instead: import a labelled reference set (JSON lines of {name, url, settings, samples}) into looks/<set>/ for evaluation and future training; guesses don't use it (it made them worse)"],
                                                          "name": ["type": "string", "description": "With learn: the set's name, e.g. \"Fuji X Weekly\""]]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
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
            "notes": ["type": "string"], "tags": ["type": "array", "items": ["type": "string"]], "allowDuplicate": ["type": "boolean"]], "required": ["name", "settings"]],
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
        ["name": "fuji_sync_slots", "description": "Camera → library: every recipe on the connected camera (C1–C7, and FS1–FS3 on an X-E5) that the library doesn't have is added as the user's own (status mine, named after the slot's name on the camera, source camera), with the user's photos shot with it (their Fujifilm JPEGs' EXIF via Spotlight or the given folders) as samples; recipes already in the library without photos get them. FS positions take their WB shift / toning from those photos (else marked uncertain). Never removes or renames. dryRun lists without writing. Photos need exiftool.",
         "inputSchema": ["type": "object", "properties": ["folders": ["type": "array", "items": ["type": "string"], "description": "Where your photos are (default: every Fujifilm JPEG Spotlight knows)"], "photos": ["type": "boolean", "description": "Look for your photos (default true)"], "dryRun": ["type": "boolean"]]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_import_photos", "description": "Find the recipes the user actually shot with from their Fujifilm JPEGs' EXIF (every Fuji JPEG stores its recipe), grouping identical settings. Recipes already in the library get shot counts and sample photos; new ones are added as status mine with a placeholder name. dryRun lists without writing. Needs exiftool.",
         "inputSchema": ["type": "object", "properties": ["folders": ["type": "array", "items": ["type": "string"]], "spotlight": ["type": "boolean", "description": "Every Fujifilm JPEG Spotlight knows (default when no folders)"], "min": ["type": "integer", "description": "Ignore recipes with fewer shots (default 3)"], "dryRun": ["type": "boolean"]]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_backup", "description": "Save a snapshot of every slot on the connected camera to the library's backups folder. Changes nothing on the camera.",
         "inputSchema": ["type": "object", "properties": ["reason": ["type": "string"]]], "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_inbox", "description": "The inbox: reels, posts and screenshots waiting to become recipes (from the share sheet, pasted links, Instagram's saved-posts export, or you). Each item: id, url or image file, source, status (queued, read, kept, skipped, failed), recipe slug once read, note. To read a queued reel use the /recipe skill (transcribe --visual), save it with fuji_save_recipe (status to-try, credit), then fuji_inbox_resolve {id, status: read, recipe, note}. The owner keeps or skips it in the app.",
         "inputSchema": ["type": "object", "properties": ["status": ["type": "string", "enum": InboxItem.Status.allCases.map(\.rawValue)], "limit": ["type": "integer", "description": "Default 50"]]], "annotations": ro],
        ["name": "fuji_inbox_add", "description": "Queue links in the inbox: every Instagram reel/post, TikTok or YouTube short link found in text (paste many at once, or the contents of Instagram's saved-posts export). Already-queued links are skipped.",
         "inputSchema": ["type": "object", "properties": ["text": ["type": "string"], "file": ["type": "string", "description": "Path to a file to scan for links instead, e.g. saved_posts.json from Instagram's \"Download your information\""]]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_inbox_resolve", "description": "Mark an inbox item: read (a recipe was saved: pass its slug and a note like \"1 value to check\"), kept, skipped, or failed (with why).",
         "inputSchema": ["type": "object", "properties": ["id": ["type": "string"], "status": ["type": "string", "enum": InboxItem.Status.allCases.map(\.rawValue)], "recipe": ["type": "string"], "note": ["type": "string"]], "required": ["id", "status"]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_slot_history", "description": "What a camera slot (C1–C7, FS1–FS3) holds now and what it held before, with dates, newest first. Every write and every connect records it, so an old recipe can be put back with fuji_plan_write.",
         "inputSchema": ["type": "object", "properties": ["slot": ["type": "string"]], "required": ["slot"]], "annotations": ro],
        ["name": "fuji_tag", "description": "Add or remove tags on a recipe (\"Leica style\", \"Warm\", \"Cool\", \"B&W\", \"Bright day\", \"Night\", \"Film\", \"Punchy\", \"Soft\", or the owner's own). Tags describe the look; the app filters by them.",
         "inputSchema": ["type": "object", "properties": ["recipe": recipeArg, "add": ["type": "array", "items": ["type": "string"]], "remove": ["type": "array", "items": ["type": "string"]]], "required": ["recipe"]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_edit_recipe", "description": "Change a recipe's name, description (notes), status (favorite, mine, tried, to-try, rejected), creator or source link. Only the fields given change; the slug stays, so its photos stay. Camera settings aren't edited here (save a new recipe instead).",
         "inputSchema": ["type": "object", "properties": ["recipe": recipeArg, "name": ["type": "string"], "notes": ["type": "string"],
                                                          "status": ["type": "string", "enum": Values.status], "creator": ["type": "string"], "url": ["type": "string"]],
                         "required": ["recipe"]],
         "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_preferences", "description": "Library-wide choices shared with the app. clarity (default false): Clarity other than 0 makes the camera stop 1–3 s after every shot to store it, so while it's false every slot is written and every fuji_render made with Clarity 0 (recipes keep their own value). Pass clarity to change it, only when the user asks; it doesn't touch the camera: plan a write of the slots afterwards so they follow.",
         "inputSchema": ["type": "object", "properties": ["clarity": ["type": "boolean"]]], "annotations": ["readOnlyHint": false, "destructiveHint": false]],
        ["name": "fuji_plan_write", "description": """
         Prepare writing recipes to the camera's custom slots WITHOUT writing; returns a plan id and a preview of every change (slot, old → new, field by field) to show the user. Operations:
         • {slot: "C3" or "FS1"…"FS3", recipe: "<slug or name>", name?: "<slot name, ≤25 ASCII, C slots only>"} — a library recipe into a slot (FS1–FS3: the film simulation dial, X-E5)
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
        case "fuji_sync_slots": return try await syncSlots(a)
        case "fuji_recipes": return try recipes(a)
        case "fuji_recipe": return try recipe(a)
        case "fuji_compare": return try await compare(a)
        case "fuji_render": return try await render(a)
        case "fuji_match_look":
            if a["evaluate"] as? Bool == true || a["learn"] != nil {
                if let set = a["learn"] as? String {
                    let name = a["name"] as? String ?? "Reference"
                    let n = try LookIndex.importSet(jsonl: URL(fileURLWithPath: (set as NSString).expandingTildeInPath), name: name, into: library)
                    _ = LookIndex.load(library)
                    return ["imported": n.recipes, "photos": n.photos, "set": name] as JSON
                }
                let index = LookIndex.load(library)
                let refs = LookIndex.referenceRecipes(library)
                let mine = try library.recipes()
                let ev = LookMatch.evaluate(index: index, recipes: mine + refs) { $0.status != "reference" }
                var report = "Your library's photos, learning from everything:\n" + ev.text
                var numbers: JSON = ["library": plain(ev)]
                if !refs.isEmpty {
                    let alone = LookMatch.evaluate(index: index, recipes: mine)
                    let theirs = LookMatch.evaluate(index: index, recipes: mine + refs) { $0.status == "reference" }
                    report += "\n\nThe same photos, learning from your library only:\n" + alone.text
                    report += "\n\nReference sets' photos, learning from everything:\n" + theirs.text
                    numbers["libraryOnly"] = plain(alone); numbers["reference"] = plain(theirs)
                }
                return ["report": report, "numbers": numbers] as JSON
            }
            return try await matchLook(a)
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
        case "fuji_inbox":
            var items = library.inbox()
            if let s = a["status"] as? String { items = items.filter { $0.status.rawValue == s } }
            let limit = a["limit"] as? Int ?? 50
            let counts = Dictionary(grouping: library.inbox(), by: { $0.status.rawValue }).mapValues(\.count)
            return ["counts": counts, "items": plain(Array(items.prefix(limit)))] as JSON
        case "fuji_inbox_add":
            var text = a["text"] as? String ?? ""
            if let f = a["file"] as? String { text += (try? String(contentsOfFile: (f as NSString).expandingTildeInPath, encoding: .utf8)) ?? "" }
            let added = try library.addToInbox(text: text, source: a["file"] != nil ? "instagram-export" : "claude")
            return ["added": added.count, "inbox": library.inbox().filter { $0.status == .queued }.count] as JSON
        case "fuji_inbox_resolve":
            guard let status = InboxItem.Status(rawValue: try str(a, "status")) else { throw ToolError("status: queued, read, kept, skipped or failed") }
            try library.updateInbox(try str(a, "id"), status: status, recipe: a["recipe"] as? String, note: a["note"] as? String)
            return ["ok": true] as JSON
        case "fuji_slot_history":
            let cam = try await Cameras.shared.require()
            let info = try await cam.deviceInfo()
            return plain(library.history(info, slot: try str(a, "slot").uppercased()))
        case "fuji_tag":
            var r = try library.recipe(str(a, "recipe"))
            var tags = r.tags ?? []
            for t in a["add"] as? [String] ?? [] where !tags.contains(t) { tags.append(t) }
            tags.removeAll { (a["remove"] as? [String] ?? []).contains($0) }
            r.tags = tags.isEmpty ? nil : tags
            try library.save(r, allowDuplicate: true)
            return ["recipe": r.slug, "tags": tags] as JSON
        case "fuji_edit_recipe":
            var r = try library.recipe(str(a, "recipe"))
            if let v = a["name"] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty { r.name = v.trimmingCharacters(in: .whitespaces) }
            if let v = a["notes"] as? String { r.notes = v.isEmpty ? nil : v }
            if let v = a["status"] as? String {
                guard Values.status.contains(v) else { throw ToolError("status must be one of \(Values.status.joined(separator: ", "))") }
                r.status = v
            }
            for key in ["creator", "url"] {
                guard let v = a[key] as? String else { continue }
                if r.source == nil { r.source = Recipe.Source(kind: "manual") }
                if key == "creator" { r.source?.creator = v.isEmpty ? nil : v } else { r.source?.url = v.isEmpty ? nil : v }
            }
            return plain(try library.save(r, allowDuplicate: true))
        case "fuji_preferences":
            var p = library.preferences
            if let v = a["clarity"] as? Bool { p.clarity = v; try library.setPreferences(p) }
            let using = (try library.recipes()).filter { $0.settings.clarity != 0 }.map(\.slug)
            return ["clarity": p.clarity,
                    "note": p.clarity ? "Clarity is on: slots get each recipe's own Clarity. \(Preferences.clarityCost)"
                                      : "Clarity is off: slots are written and photos rendered with Clarity 0, so the camera doesn't stop to store each shot. Recipes keep their value.",
                    "recipesWithClarity": using] as JSON
        case "fuji_plan_write": return try await planWrite(a["operations"] as? [JSON] ?? [])
        case "fuji_apply_write": return try await applyWrite(str(a, "planId"))
        default: throw ToolError("Unknown tool \(name).")
        }
    }

    func render(_ a: JSON) async throws -> Any {
        let raw = URL(fileURLWithPath: (try str(a, "raw") as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: raw.path) else { throw ToolError("No file at \(raw.path).") }
        let full = a["full"] as? Bool ?? false
        let all = try library.recipes()
        let chosen: [Recipe] = try (a["recipes"] as? [String]).map { try $0.map { try library.recipe($0) } }
            ?? all.filter { $0.status == "favorite" || $0.status == "to-try" }
        let cache = RenderCache(library: library)
        var out: [JSON] = []
        var base: ConversionProfile?
        var cam: FujiCamera?
        let prefs = library.preferences
        for r in chosen {
            let settings = r.settings.forCamera(prefs)   // what the camera would shoot: Clarity 0 while it's off
            if let hit = cache.cached(raw: raw, settings: settings, full: full) {
                out.append(["recipe": r.slug, "name": r.name, "jpeg": hit.path, "cached": true]); continue
            }
            if cam == nil { cam = try await Cameras.shared.require() }
            if base == nil { base = try await cam!.uploadRAF(try Data(contentsOf: raw)) }
            let made = try await cam!.render(settings, base: base!, full: full)
            let u = try cache.store(made.jpeg, raw: raw, settings: settings, full: full)
            out.append(["recipe": r.slug, "name": r.name, "jpeg": u.path, "seconds": (made.seconds * 10).rounded() / 10, "notes": made.notes])
        }
        return ["raw": raw.path, "renders": out] as JSON
    }

    func matchLook(_ a: JSON) async throws -> Any {
        let image = URL(fileURLWithPath: (try str(a, "image") as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: image.path) else { throw ToolError("No file at \(image.path).") }
        let stats = try LookStats.measure(file: image)
        // Learns from the library's own photos only: measured with fuji match --evaluate, adding a reference set such as
        // Fuji X Weekly's photos made guesses on the owner's photos worse (film 40% → 30%), see ADR 0005.
        let guess = LookMatch.firstGuess(stats, index: LookIndex.load(library), recipes: try library.recipes())
        var out: JSON = ["image": image.path, "firstGuess": ["summary": guess.settings.summary, "text": guess.settings.text,
                                                             "settings": plain(guess.settings), "notes": guess.notes] as JSON,
                         "looksLike": guess.neighbours.prefix(3).map { n -> JSON in
                             var j: JSON = ["recipe": n.recipe.slug, "name": n.recipe.name, "photo": n.file]
                             if n.recipe.status == "reference" { j["from"] = n.recipe.source?.creator ?? "reference set"; j["url"] = n.recipe.source?.url ?? ""; j["inLibrary"] = false }
                             return j
                         },
                         "look": ["mono": stats.mono, "saturation": (stats.chroma * 10).rounded() / 10,
                                  "castMid": stats.castMid.map { ($0 * 10).rounded() / 10 }, "tone": stats.tone.map { $0.rounded() }] as JSON]
        var best: (RecipeSettings, Int?, Data?) = (guess.settings, nil, nil)
        var rawURL: URL?
        if let r = a["raw"] as? String {
            let raw = URL(fileURLWithPath: (r as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: raw.path) else { throw ToolError("No file at \(raw.path).") }
            rawURL = raw
            let cache = RenderCache(library: library)
            var cam: FujiCamera?
            var base: ConversionProfile?
            let start = Date()
            let found = try await LookMatch.refine(reference: stats, start: guess.settings, budget: a["budget"] as? Int ?? 60) { s in
                if let hit = cache.cached(raw: raw, settings: s), let d = try? Data(contentsOf: hit) { return d }
                if cam == nil { cam = try await Cameras.shared.require() }
                if base == nil { base = try await cam!.uploadRAF(try Data(contentsOf: raw)) }
                let made = try await cam!.render(s, base: base!)
                try cache.store(made.jpeg, raw: raw, settings: s)
                return made.jpeg
            }
            out["raw"] = raw.path
            out["seconds"] = Int(Date().timeIntervalSince(start))
            out["matches"] = found.map { c -> JSON in
                ["match": c.match, "summary": c.settings.summary, "text": c.settings.text, "settings": plain(c.settings),
                 "jpeg": cache.url(raw: raw, settings: c.settings).path]
            }
            if let top = found.first { best = (top.settings, top.match, top.jpeg) }
        }
        if let name = a["save"] as? String, !name.isEmpty {
            let saved = try library.saveMatched(best.0, name: name, reference: image, raw: rawURL, match: best.1, render: best.2, notes: guess.notes)
            out[saved.existing ? "alreadyInLibrary" : "saved"] = saved.recipe.slug
        }
        return out
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
            do { out["slots"] = try await cam.bankCount() } catch { out["slotsError"] = "\(error)" }
            out["note"] = "The camera's menu is locked while it's connected in this mode. FS1–FS3 on the film simulation dial are written through the camera's settings file (fuji_plan_write slot \"FS1\"…\"FS3\"; WB shift and B&W toning stay as set on the camera). The dial overrides a C slot's film simulation unless it's set to C."
        } else {
            out["advice"] = "The camera is in \(mode.label) mode, where its custom slots can't be reached. \(USBMode.howToSet)"
        }
        return out
    }

    func slots() async throws -> Any {
        let cam = try await Cameras.shared.require()
        let banks = try await cam.readAll()
        if let i = try? await cam.deviceInfo() { library.observe(i, slots: banks.map { ($0.slot, $0.name, $0.settings) }) }
        var out = banks.map { b -> JSON in
            var o: JSON = ["slot": b.slot, "name": b.name, "summary": b.settings.summary, "settings": plain(b.settings)]
            if let (r, notes) = library.matchOnCamera(b.settings) { o["recipe"] = r.slug; o["recipeName"] = r.name; if !notes.isEmpty { o["cameraLimits"] = notes } }
            return o
        }
        // Film simulation dial (X-E5): FS1–FS3 live only in the camera's settings file; written through it (ADR 0004).
        let info = try await cam.deviceInfo()
        if SettingsFile.layout(model: info.model) != nil, let file = try? await cam.downloadSettingsBackup(),
           let dial = SettingsFile.dialSlots(file, model: info.model) {
            out += dial.map { d -> JSON in
                var o: JSON = ["slot": d.slot, "dial": true, "summary": d.settings.summary, "settings": plain(d.settings),
                               "unverified": d.unverified]
                if let (r, notes) = library.matchOnCamera(d.settings, dial: true) { o["recipe"] = r.slug; o["recipeName"] = r.name; if !notes.isEmpty { o["cameraLimits"] = notes } }
                return o
            }
        }
        return out
    }

    func syncSlots(_ a: JSON) async throws -> Any {
        let cam = try await Cameras.shared.require()
        let info = try await cam.deviceInfo()
        var contents = try await cam.readAll().map { SlotSync.SlotContents(slot: $0.slot, name: $0.name, settings: $0.settings, dial: false) }
        if SettingsFile.layout(model: info.model) != nil, let file = try? await cam.downloadSettingsBackup(),
           let dial = SettingsFile.dialSlots(file, model: info.model) {
            contents += dial.map { SlotSync.SlotContents(slot: $0.slot, name: "", settings: $0.settings, dial: true) }
        }
        let photos = (a["photos"] as? Bool ?? true) ? SlotSync.photos(in: a["folders"] as? [String]) : nil
        let r = try SlotSync.run(contents, library: library, camera: info.model, photos: photos, dryRun: a["dryRun"] as? Bool ?? false)
        return ["summary": r.summary, "dryRun": a["dryRun"] as? Bool ?? false, "photosSearched": photos != nil,
                "added": r.added.map { ["slug": $0.slug, "name": $0.name, "summary": $0.settings.summary, "shots": $0.shots ?? 0,
                                        "uncertain": $0.uncertain ?? []] as JSON },
                "photosAttached": r.photosFor, "slots": r.known.map { ["slot": $0.slot, "recipe": $0.slug] }]
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
        // C1…Cn are 1…n; FS1…FS3 (film simulation dial, settings file) are 101…103.
        let dialSlots = SettingsFile.layout(model: info.model)?.slots ?? 0
        func slotIndex(_ s: String) throws -> Int {
            let u = s.uppercased()
            if u.hasPrefix("FS"), let n = Int(u.dropFirst(2)), (1...max(1, dialSlots)).contains(n), dialSlots > 0 { return 100 + n }
            guard let n = Int(u.dropFirst()), u.hasPrefix("C"), n >= 1, n <= count else {
                throw ToolError("\(s) isn't a slot on the \(info.model) (C1…C\(count)\(dialSlots > 0 ? ", FS1…FS\(dialSlots)" : "")).")
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
        // Clarity off (the default): nothing reaches the camera with Clarity, it makes every shot wait to be stored.
        var preview: [String] = []
        if !library.preferences.clarity {
            var held: [String] = []
            for i in writes.indices where writes[i].settings.clarity != 0 {
                let c = writes[i].settings.clarity
                held.append("\(writes[i].slot > 100 ? "FS\(writes[i].slot - 100)" : "C\(writes[i].slot)") (\(writes[i].label) has \(c > 0 ? "+" : "−")\(abs(c)))")
                writes[i].settings.clarity = 0
            }
            if !held.isEmpty {
                preview.append("Clarity stays 0 in \(held.joined(separator: ", ")): it makes the camera stop 1–3 s to store every shot. fuji_preferences {clarity: true} allows it.")
            }
        }
        var dialNow: [SettingsFile.DialSlot]?
        for w in writes where w.slot > 100 {
            if dialNow == nil { dialNow = SettingsFile.dialSlots(try await cam.downloadSettingsBackup(), model: info.model) }
            guard let cur = dialNow?[w.slot - 101] else { throw ToolError("Couldn't read FS\(w.slot - 100) from the camera's settings file.") }
            let diffs = cur.settings.differences(to: w.settings)
            preview.append("FS\(w.slot - 100) \(cur.settings.film) → \(w.label)" + (diffs.isEmpty ? ": already the same, nothing to write" : "\n    " + diffs.joined(separator: "\n    ")) +
                           "\n    (WB shift and B&W toning stay as set on the camera; FS positions have no name)")
        }
        for w in writes where w.slot < 100 {
            let current = try await cam.readBank(w.slot)
            let name = PTPString.bankName(w.name.isEmpty && !w.exactName ? current.name : w.name)
            var diffs = current.settings.differences(to: w.settings)
            if name != current.name { diffs.insert("name: \(current.name.isEmpty ? "—" : current.name) → \(name)", at: 0) }
            preview.append("C\(w.slot) \(current.name.isEmpty ? "(unnamed)" : current.name) → \(w.label)" +
                           (diffs.isEmpty ? ": already the same, nothing to write" : "\n    " + diffs.joined(separator: "\n    ")))
        }
        preview.append("A backup of all \(count) slots is saved first\(writes.contains { $0.slot > 100 } ? ", plus the camera's whole settings file before FS writes" : ""). Each slot is read back after writing.")
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
        let backupURL = try await backup(reason: "Before writing \(plan.writes.map { $0.slot > 100 ? "FS\($0.slot - 100)" : "C\($0.slot)" }.joined(separator: ", "))")
        var reports: [Any] = []
        for w in plan.writes where w.slot < 100 {
            let report = try await cam.writeBank(w.slot, settings: w.settings, name: w.name.isEmpty && !w.exactName ? nil : w.name)
            library.recordWrite(info, slot: "C\(w.slot)", name: report.name, settings: report.after, how: w.exactName ? "put back" : "written")
            var o = plain(report) as? JSON ?? [:]
            o["ok"] = report.ok
            reports.append(o)
        }
        for w in plan.writes where w.slot > 100 {
            let (report, prior) = try await cam.writeDialSlot(w.slot - 101, settings: w.settings)
            let dir = library.root.appendingPathComponent("backups")
            let stamp = Date().isoStamp.prefix(19).replacingOccurrences(of: ":", with: "")
            try? prior.write(to: dir.appendingPathComponent("\(stamp)-\(Recipe.slugify(info.model))-settings-before-fs\(w.slot - 100).dat"))
            library.recordWrite(info, slot: report.slot, name: "", settings: report.after, how: w.exactName ? "put back" : "written")
            reports.append(["slot": report.slot, "ok": report.ok, "after": report.after.summary, "mismatches": report.mismatches,
                            "keptAsOnCamera": report.kept, "unexpectedBytes": report.unexpected] as JSON)
        }
        plans[id] = nil
        return ["backup": backupURL.path, "slots": reports,
                "note": "To shoot with a slot: unplug, turn the film simulation dial to C, press Q, and turn the rear command dial to the slot (SELECT CUSTOM SETTING). On a named film or FS1–FS3 the dial overrides the slot's film simulation."] as JSON
    }
}
