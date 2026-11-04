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
