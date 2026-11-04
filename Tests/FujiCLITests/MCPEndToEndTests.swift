import XCTest

/// Runs `fuji mcp` (the server Claude Code and Claude Desktop start) with FUJI_SIMULATE=1 and a temporary library,
/// and drives it over stdio JSON-RPC the way an agent does.
final class MCPEndToEndTests: XCTestCase {
    var lib: URL!
    var process: Process!
    var input: FileHandle!
    var output: FileHandle!
    var buffer = Data()
    var nextID = 1

    var fuji: URL {
        var dir = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("fuji").path) { dir = dir.deletingLastPathComponent() }
        return dir.appendingPathComponent("fuji")
    }

    override func setUpWithError() throws {
        lib = FileManager.default.temporaryDirectory.appendingPathComponent("fuji-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        process = Process()
        process.executableURL = fuji
        process.arguments = ["mcp"]
        process.environment = ["FUJI_SIMULATE": "1", "FUJI_RECIPES": lib.path, "HOME": NSHomeDirectory()]
        let i = Pipe(), o = Pipe()
        process.standardInput = i; process.standardOutput = o; process.standardError = Pipe()
        input = i.fileHandleForWriting; output = o.fileHandleForReading
        try process.run()
        _ = try call("initialize", [:])
    }

    override func tearDown() {
        try? input.close()
        process.terminate()
        try? FileManager.default.removeItem(at: lib)
    }

    func call(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        let id = nextID; nextID += 1
        let msg = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        input.write(msg + Data("\n".utf8))
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]; buffer = Data(buffer[(nl + 1)...])
                if let m = try JSONSerialization.jsonObject(with: line) as? [String: Any], m["id"] as? Int == id { return m }
                continue
            }
            let chunk = output.availableData
            if chunk.isEmpty { usleep(20_000) } else { buffer += chunk }
        }
        throw NSError(domain: "e2e", code: 1, userInfo: [NSLocalizedDescriptionKey: "no answer to \(method)"])
    }

    /// A tool call's JSON result (the text content), failing the test on a tool error.
    func tool(_ name: String, _ args: [String: Any] = [:], file: StaticString = #filePath, line: UInt = #line) throws -> Any {
        let r = try call("tools/call", ["name": name, "arguments": args])
        let result = try XCTUnwrap(r["result"] as? [String: Any], "\(r)", file: file, line: line)
        let text = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertNotEqual(result["isError"] as? Bool, true, text, file: file, line: line)
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)) ?? text
    }

    func testToolsAreListed() throws {
        let r = try call("tools/list", [:])
        let names = ((r["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        for t in ["fuji_camera", "fuji_slots", "fuji_save_recipe", "fuji_edit_recipe", "fuji_plan_write", "fuji_apply_write",
                  "fuji_render", "fuji_match_look", "fuji_inbox_add", "fuji_slot_history", "fuji_tag"] {
            XCTAssertTrue(names.contains(t), "missing \(t)")
        }
    }

    /// Save a recipe → plan C3 and FS2 → preview → apply → read back → history → edit → render twice (cached).
    func testRecipeToCameraToStudio() throws {
        let saved = try tool("fuji_save_recipe", ["name": "E2E Chrome", "settings": [
            "film": "Classic Chrome", "grain_roughness": "Weak", "grain_size": "Small", "color_chrome": "Strong",
            "color_chrome_fx_blue": "Off", "wb": "Daylight", "wb_red": 2, "wb_blue": -5, "dynamic_range": "DR100",
            "d_range_priority": "Off", "highlight": 0, "shadow": 2, "color": 2, "sharpness": 1, "high_iso_nr": -4, "clarity": 3]]) as? [String: Any]
        let slug = try XCTUnwrap(saved?["saved"] as? String)

        let camera = try tool("fuji_camera") as? [String: Any]
        XCTAssertEqual(camera?["connected"] as? Bool, true)

        let plan = try XCTUnwrap(try tool("fuji_plan_write", ["operations": [["slot": "C3", "recipe": slug], ["slot": "FS2", "recipe": slug]]]) as? [String: Any])
        let preview = (plan["preview"] as? [String] ?? []).joined(separator: "\n")
        XCTAssertTrue(preview.contains("C3"), preview); XCTAssertTrue(preview.contains("FS2"), preview)
        let applied = try XCTUnwrap(try tool("fuji_apply_write", ["planId": plan["planId"] as! String]) as? [String: Any])
        let reports = applied["slots"] as? [[String: Any]] ?? []
        XCTAssertEqual(reports.count, 2)
        XCTAssertTrue(reports.allSatisfy { $0["ok"] as? Bool == true }, "\(reports)")

        let slots = try XCTUnwrap(try tool("fuji_slots") as? [[String: Any]])
        XCTAssertEqual(slots.first { $0["slot"] as? String == "C3" }?["recipe"] as? String, slug)
        XCTAssertEqual(slots.first { $0["slot"] as? String == "FS2" }?["recipe"] as? String, slug)
        let history = "\(try tool("fuji_slot_history", ["slot": "C3"]))"
        XCTAssertTrue(history.contains("Classic Chrome"), history)

        _ = try tool("fuji_edit_recipe", ["recipe": slug, "name": "E2E Chrome Renamed", "status": "favorite"])
        let raw = lib.appendingPathComponent("photo.RAF")
        try (Data("FUJIFILMCCD-RAW 0201FF383501X-E5".utf8) + Data(count: 4000)).write(to: raw)
        let first = try XCTUnwrap((try tool("fuji_render", ["raw": raw.path, "recipes": [slug]]) as? [String: Any])?["renders"] as? [[String: Any]])
        XCTAssertEqual(first.count, 1)
        XCTAssertNil(first[0]["cached"])
        let jpeg = try XCTUnwrap(first[0]["jpeg"] as? String)
        XCTAssertGreaterThan((try Data(contentsOf: URL(fileURLWithPath: jpeg))).count, 100)
        let second = try XCTUnwrap((try tool("fuji_render", ["raw": raw.path, "recipes": [slug]]) as? [String: Any])?["renders"] as? [[String: Any]])
        XCTAssertEqual(second[0]["cached"] as? Bool, true, "a second render of the same recipe comes from the cache")
    }

    func testAddRecipesInbox() throws {
        let added = try XCTUnwrap(try tool("fuji_inbox_add", ["text": "https://www.instagram.com/reel/ABC123/ and https://www.instagram.com/p/XYZ9/"]) as? [String: Any])
        XCTAssertEqual(added["added"] as? Int, 2)
        let again = try XCTUnwrap(try tool("fuji_inbox_add", ["text": "https://www.instagram.com/reel/ABC123/"]) as? [String: Any])
        XCTAssertEqual(again["added"] as? Int, 0, "a link already queued isn't added twice")
        let inbox = "\(try tool("fuji_inbox"))"
        XCTAssertTrue(inbox.contains("XYZ9"), inbox)
    }

    /// Match a look over MCP: a photo developed with a known recipe goes in; the camera search on the same RAW finds
    /// a recipe whose render looks the same, saves it, and the accuracy report runs on the library.
    func testMatchALook() throws {
        var target: [String: Any] = ["film": "Classic Neg.", "wb": "Auto", "wb_red": 3, "wb_blue": -4, "dynamic_range": "DR100",
                                     "highlight": -1, "shadow": 1, "color": 2]
        target["grain_roughness"] = "Off"
        let saved = try XCTUnwrap(try tool("fuji_save_recipe", ["name": "E2E Target", "settings": target]) as? [String: Any])
        let slug = try XCTUnwrap(saved["saved"] as? String)
        let raw = lib.appendingPathComponent("photo.RAF")
        try (Data("FUJIFILMCCD-RAW 0201FF383501X-E5".utf8) + Data(count: 4000)).write(to: raw)
        let rendered = try XCTUnwrap(((try tool("fuji_render", ["raw": raw.path, "recipes": [slug]]) as? [String: Any])?["renders"] as? [[String: Any]])?.first?["jpeg"] as? String)
        let reference = lib.appendingPathComponent("someone else's photo.jpg")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: rendered), to: reference)

        let guessOnly = try XCTUnwrap(try tool("fuji_match_look", ["image": reference.path]) as? [String: Any])
        XCTAssertNotNil((guessOnly["firstGuess"] as? [String: Any])?["summary"], "a first guess needs no camera")
        XCTAssertNil(guessOnly["matches"])

        let result = try XCTUnwrap(try tool("fuji_match_look", ["image": reference.path, "raw": raw.path, "budget": 50, "save": "E2E Matched"]) as? [String: Any])
        let matches = try XCTUnwrap(result["matches"] as? [[String: Any]])
        XCTAssertFalse(matches.isEmpty)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(matches.first?["match"] as? Int), 85, "\(matches.first ?? [:])")
        let jpeg = try XCTUnwrap(matches.first?["jpeg"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jpeg), "the closest render is kept for the app to show")
        XCTAssertTrue(result["saved"] != nil || result["alreadyInLibrary"] != nil, "\(result)")

        let report = "\(try tool("fuji_match_look", ["evaluate": true]))"
        XCTAssertTrue(report.contains("sample photos"), report)
    }
}
