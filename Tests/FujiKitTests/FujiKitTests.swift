import XCTest
@testable import FujiKit

final class CodecTests: XCTestCase {
    func testEveryFilmRoundTrips() {
        for (i, film) in Film.all.enumerated() {
            var s = RecipeSettings(); s.film = film; s.normalize()
            let raw = BankCodec.encode(s)
            XCTAssertEqual(raw[.film], UInt16(i + 1))
            XCTAssertEqual(BankCodec.decode(raw), s, film)
        }
    }

    func testGrainOffReadsBackAsSixOrSeven() {
        for raw: UInt16 in [1, 6, 7] { XCTAssertEqual(BankCodec.decode([.grain: raw]).grainRoughness, "Off") }
        var s = RecipeSettings(); s.grainRoughness = "Strong"; s.grainSize = "Large"
        XCTAssertEqual(BankCodec.encode(s)[.grain], 5)
    }

    func testSignedTenthsAndLookups() {
        var s = RecipeSettings(); s.highlight = -1.5; s.shadow = 4; s.color = -4; s.sharpness = -2; s.clarity = -5
        s.highIsoNr = -4; s.wbRed = 1; s.wbBlue = -3; s.wb = "Kelvin"; s.wbKelvin = 3600; s.dynamicRange = "Auto"
        let raw = BankCodec.encode(s)
        XCTAssertEqual(raw[.highlight], UInt16(bitPattern: -15))
        XCTAssertEqual(raw[.highIsoNr], 0x8000)
        XCTAssertEqual(raw[.wbBlue], UInt16(bitPattern: -3))          // shifts are not ×10
        XCTAssertEqual(raw[.wbMode], 0x8007)
        XCTAssertEqual(raw[.dynamicRange], 0xFFFF)
        var expected = s; expected.normalize()
        XCTAssertEqual(BankCodec.decode(raw), expected)
    }

    func testPriorityOnLeavesDynamicRangeAndToneAlone() {
        var s = RecipeSettings(); s.dRangePriority = "Auto"
        let raw = BankCodec.encode(s)
        XCTAssertEqual(raw[.dRangePriority], 0x8000)
        XCTAssertNil(raw[.dynamicRange]); XCTAssertNil(raw[.highlight])
        XCTAssertEqual(BankCodec.writeOrder(turningPriorityOff: true).prefix(3), [.film, .dRangePriority, .dynamicRange])
    }

    func testBankNameString() {
        XCTAssertEqual(PTPString.encode(""), Data([1, 0, 0]))
        XCTAssertEqual(PTPString.decode(PTPString.encode("CLASSIC NEG")), "CLASSIC NEG")
        XCTAssertEqual(PTPString.bankName("Café • Summer recipe with a very long name"), "Caf  Summer recipe with a")
    }

    func testRecipeChecks() {
        var r = Recipe(slug: "x", name: "X", settings: RecipeSettings())
        XCTAssertEqual(r.problems, [])
        r.settings.highlight = 0.3; r.settings.wbRed = 12; r.status = "maybe"
        XCTAssertEqual(Set(r.problems), ["highlight=0.3", "wb_red=12.0", "status=maybe"])
        XCTAssertEqual(Recipe.slugify("Kodak Portra 400 — v2"), "kodak-portra-400-v2")
    }

    func testFileFormatMatchesTheSkill() throws {
        // A file written by the /recipe skill's Python script.
        let json = #"{"slug":"acros-g-e828be","name":"Green Acros","status":"mine","settings":{"film":"Acros+G","grain_roughness":"Off","grain_size":"Off","color_chrome":"Off","color_chrome_fx_blue":"Off","wb":"Auto","wb_kelvin":null,"wb_red":0,"wb_blue":0,"dynamic_range":"DR100","d_range_priority":"Off","highlight":0,"shadow":0,"color":null,"mono_warm_cool":0,"mono_magenta_green":0,"sharpness":0,"high_iso_nr":-4,"clarity":0},"shooting":{},"source":{"kind":"exif","date_added":"2026-11-04"},"shots":62,"cameras":["X-E5"],"first_shot":"2026-06-10","last_shot":"2026-07-11","samples":[],"uncertain":[],"notes":""}"#
        let r = try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
        XCTAssertEqual(r.settings.film, "Acros+G"); XCTAssertEqual(r.shots, 62); XCTAssertEqual(r.source?.dateAdded, "2026-11-04")
        let out = String(decoding: try Library.encoder.encode(r), as: UTF8.self)
        XCTAssertTrue(out.contains("\"color\" : null") && out.contains("\"first_shot\" : \"2026-06-10\""))
    }
}

final class CameraTests: XCTestCase {
    func testReadAllFromSimulatedXE5() async throws {
        let cam = FujiCamera(transport: SimulatedCamera())
        let info = try await cam.deviceInfo()
        XCTAssertEqual(info.model, "X-E5"); XCTAssertEqual(info.firmware, "1.10")
        let banks = try await cam.readAll()
        XCTAssertEqual(banks.count, 7)
        XCTAssertEqual(banks[0].name, "GREEN ACROS"); XCTAssertEqual(banks[0].settings.film, "Acros+G")
        XCTAssertEqual(banks[1].settings.wbBlue, -3)
    }

    func testWriteMonoToColourAndBackReadsBackClean() async throws {
        let cam = FujiCamera(transport: SimulatedCamera())
        var s = RecipeSettings(); s.film = "Classic Chrome"; s.grainRoughness = "Weak"; s.color = 2; s.wb = "Kelvin"; s.wbKelvin = 5200; s.wbRed = 2
        var r = try await cam.writeBank(1, settings: s, name: "Summer")
        XCTAssertTrue(r.ok, "\(r.refused) \(r.mismatches)")
        XCTAssertEqual(r.name, "Summer")
        var back = RecipeSettings(); back.film = "Acros+G"; back.highIsoNr = -4; back.dRangePriority = "Strong"
        r = try await cam.writeBank(1, settings: back, name: "GREEN ACROS")
        XCTAssertTrue(r.ok, "\(r.refused) \(r.mismatches)")
        // Writing the same again changes nothing.
        r = try await cam.writeBank(1, settings: back, name: "GREEN ACROS")
        XCTAssertTrue(r.written.isEmpty)
    }

    func testSlotCountAndWrongMode() async throws {
        let sim = SimulatedCamera(model: "X-M5", banks: 4)
        let cam = FujiCamera(transport: sim)
        let n = try await cam.bankCount()
        XCTAssertEqual(n, 4)
        sim.usbMode = nil
        let mode = try await cam.usbMode()
        XCTAssertEqual(mode, .cardReader)
    }
}

final class SettingsFileTests: XCTestCase {
    /// FS1 bytes as read from the owner's X-E5 (fw 1.12), checked against the EXIF of 39 photos shot with it.
    func testXE5DialSlotDecodes() throws {
        var d = Data("FUJIFILM".utf8) + Data(count: SettingsFile.xe5.size - 8)
        let fs1: [String: Int] = ["film": 16, "wb": 0, "nr": 0, "clarity": 6, "wc": 18, "mg": 18, "dr": 1, "color": 6, "sharp": 6,
                                  "hi": 0, "sh": 2, "cc": 2, "fxb": 2, "grain": 0, "gsize": 1, "r": 9, "b": 9]
        for (k, v) in fs1 { d[SettingsFile.xe5.fields[k]!.offset] = UInt8(v) }
        let s = try XCTUnwrap(SettingsFile.dialSlots(d, model: "X-E5")?.first).settings
        XCTAssertEqual(s.film, "Classic Neg."); XCTAssertEqual(s.grainRoughness, "Strong"); XCTAssertEqual(s.grainSize, "Large")
        XCTAssertEqual(s.colorChrome, "Strong"); XCTAssertEqual(s.colorChromeFxBlue, "Strong"); XCTAssertEqual(s.dynamicRange, "DR100")
        XCTAssertEqual(s.highlight, -2); XCTAssertEqual(s.shadow, -1); XCTAssertEqual(s.color, 1)
        XCTAssertEqual(s.sharpness, -2); XCTAssertEqual(s.highIsoNr, -4); XCTAssertEqual(s.clarity, 0)
        XCTAssertNil(SettingsFile.dialSlots(d, model: "X-T5"))
    }
}

final class InboxAndHistoryTests: XCTestCase {
    func temp() -> Library { Library(root: FileManager.default.temporaryDirectory.appendingPathComponent("fuji-test-\(UUID().uuidString)")) }

    func testLinksFromPasteAndInstagramExport() throws {
        let export = #"{"saved_saved_media":[{"title":"x","string_map_data":{"Saved on":{"href":"https:\/\/www.instagram.com\/reel\/DAbc123_x\/?igsh=abc","timestamp":1}}},{"string_map_data":{"Saved on":{"href":"https:\/\/www.instagram.com\/p\/Cxyz789\/"}}}]}"#
        let paste = "look https://www.instagram.com/reels/DAbc123_x/ and https://www.tiktok.com/@someone/video/7412345678901234567 and https://youtu.be/AbCdEf12345"
        let lib = temp()
        let a = try lib.addToInbox(text: export, source: "instagram-export")
        XCTAssertEqual(a.map { $0.url! }, ["https://www.instagram.com/reel/DAbc123_x/", "https://www.instagram.com/p/Cxyz789/"])
        let b = try lib.addToInbox(text: paste, source: "paste")
        XCTAssertEqual(b.count, 2)                       // the reel was already queued
        XCTAssertEqual(lib.inbox().count, 4)
        try lib.updateInbox(b[0].id, status: .read, recipe: "summer-chrome", note: "1 value to check")
        XCTAssertEqual(lib.inbox().first { $0.id == b[0].id }?.status, .read)
    }

    func testSlotHistoryKeepsWhatWasThere() {
        let lib = temp()
        var cam = DeviceInfo(); cam.model = "X-E5"; cam.serial = "SIM0001"
        var neg = RecipeSettings(); neg.film = "Classic Neg."; neg.normalize()
        var chrome = RecipeSettings(); chrome.film = "Classic Chrome"; chrome.normalize()
        lib.observe(cam, slots: [("C3", "NEG", neg)])
        lib.recordWrite(cam, slot: "C3", name: "SUMMER", settings: chrome)
        let h = lib.history(cam, slot: "C3")
        XCTAssertEqual(h.map(\.name), ["SUMMER", "NEG"])
        XCTAssertNil(h[0].to); XCTAssertNotNil(h[1].to)
        lib.observe(cam, slots: [("C3", "SUMMER", chrome)])   // unchanged: no new entry
        XCTAssertEqual(lib.history(cam, slot: "C3").count, 2)
    }
}
