import ImageIO
import CoreGraphics
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

final class CameraLimitsTests: XCTestCase {
    /// A slot that kept DR100 (hidden ISO too low) or dropped the toning is still that recipe, with a note.
    func testSlotStillMatchesItsRecipe() {
        var r = RecipeSettings(); r.film = "Classic Neg."; r.dynamicRange = "DR400"; r.color = 4; r.normalize()
        var cam = r; cam.dynamicRange = "DR100"
        XCTAssertEqual(r.cameraLimitedDifferences(r), [])
        XCTAssertEqual(r.cameraLimitedDifferences(cam)?.count, 1)
        var other = cam; other.color = 2
        XCTAssertNil(r.cameraLimitedDifferences(other))                       // anything else: not this recipe
        var higher = r; higher.dynamicRange = "DR100"; var camHigher = higher; camHigher.dynamicRange = "DR400"
        XCTAssertNil(higher.cameraLimitedDifferences(camHigher))             // the camera never raises DR by itself
        var mono = RecipeSettings(); mono.film = "Acros+G"; mono.dynamicRange = "DR400"; mono.monoWarmCool = -1; mono.monoMagentaGreen = -1; mono.normalize()
        var monoCam = mono; monoCam.dynamicRange = "DR100"; monoCam.monoWarmCool = 0; monoCam.monoMagentaGreen = 0
        XCTAssertEqual(mono.cameraLimitedDifferences(monoCam)?.count, 2)
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

    /// Writing FS slots: every writable field round-trips through the reader, other slots and other bytes stay, and
    /// the checksum at 0x120 moves by exactly the byte delta (the rule the X-E5 accepted on 2026-11-04).
    func testPatchRoundTripsAndKeepsTheChecksumRule() throws {
        var d = Data("FUJIFILM".utf8) + Data(count: SettingsFile.xe5.size - 8)
        for (_, f) in SettingsFile.xe5.fields { for i in 0..<3 { d[f.offset + i * f.step] = 4 } }
        d[0x120] = 0x34; d[0x121] = 0x12
        let fs2Before = try XCTUnwrap(SettingsFile.dialSlots(d, model: "X-E5"))[1].settings
        var r = RecipeSettings()
        r.film = "Nostalgic Neg."; r.grainRoughness = "Weak"; r.grainSize = "Large"; r.colorChrome = "Strong"; r.colorChromeFxBlue = "Off"
        r.wb = "Kelvin"; r.wbKelvin = 6500; r.dynamicRange = "DR400"; r.highlight = -0.5; r.shadow = 2.5; r.color = 4
        r.sharpness = -1; r.highIsoNr = -4; r.clarity = -3
        r.normalize()
        let (out, kept) = try SettingsFile.patch(d, slot: 2, settings: r, model: "X-E5")
        let read = try XCTUnwrap(SettingsFile.dialSlots(out, model: "X-E5"))
        let fs3 = read[2].settings
        XCTAssertEqual(fs3.film, r.film); XCTAssertEqual(fs3.grainRoughness, "Weak"); XCTAssertEqual(fs3.grainSize, "Large")
        XCTAssertEqual(fs3.colorChrome, "Strong"); XCTAssertEqual(fs3.colorChromeFxBlue, "Off")
        XCTAssertEqual(fs3.wb, "Kelvin"); XCTAssertEqual(fs3.wbKelvin, 6500); XCTAssertEqual(fs3.dynamicRange, "DR400")
        XCTAssertEqual(fs3.highlight, -0.5); XCTAssertEqual(fs3.shadow, 2.5); XCTAssertEqual(fs3.color, 4)
        XCTAssertEqual(fs3.sharpness, -1); XCTAssertEqual(fs3.highIsoNr, -4); XCTAssertEqual(fs3.clarity, -3)
        XCTAssertEqual(read[1].settings, fs2Before)
        XCTAssertTrue(kept.contains("wb_red"))
        // Checksum: stored + sum of byte deltas, outside 0x120…0x121.
        let a = [UInt8](d), b = [UInt8](out)
        var delta = 0
        for i in 0..<a.count where i != 0x120 && i != 0x121 { delta += Int(b[i]) - Int(a[i]) }
        XCTAssertEqual(Int(b[0x120]) | Int(b[0x121]) << 8, (0x1234 + delta) & 0xFFFF)
        XCTAssertThrowsError(try SettingsFile.patch(d, slot: 3, settings: r, model: "X-E5"))
        XCTAssertThrowsError(try SettingsFile.patch(d.prefix(100), slot: 0, settings: r, model: "X-E5"))
    }

    /// The exact change made on the owner's X-E5 in the supervised test: FS3 Sharpness 0 → +1 is one byte and checksum −1.
    func testSupervisedTestPatch() throws {
        var d = Data("FUJIFILM".utf8) + Data(count: SettingsFile.xe5.size - 8)
        for (_, f) in SettingsFile.xe5.fields { for i in 0..<3 { d[f.offset + i * f.step] = 4 } }
        d[0x120] = 4; d[0x121] = 192
        var s = try XCTUnwrap(SettingsFile.dialSlots(d, model: "X-E5"))[2].settings
        let (same, _) = try SettingsFile.patch(d, slot: 2, settings: s, model: "X-E5")
        s.sharpness += 1
        let (out, _) = try SettingsFile.patch(same, slot: 2, settings: s, model: "X-E5")
        let diff = (0..<out.count).filter { out[$0] != same[$0] }
        XCTAssertEqual(diff, [0x120, 34760])
        XCTAssertEqual(out[34760], same[34760] - 1)
        XCTAssertEqual(out[0x120], same[0x120] - 1)
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

/// End to end against the simulated X-E5: every camera feature through the same FujiCamera calls the app and MCP use.
final class EndToEndCameraTests: XCTestCase {
    func fakeRAF(model: String = "X-E5") -> Data { Data("FUJIFILMCCD-RAW 0201FF383501\(model)".utf8) + Data(count: 4000) }

    func pixel(_ jpeg: Data) throws -> [Int] {
        let src = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return px.prefix(3).map(Int.init)
    }

    /// Studio: upload once, render several recipes; each render is a JPEG that differs by recipe, nothing is left on
    /// the camera, DR above the photo's is capped (with a note), and B&W renders are grey.
    func testStudioRendersEachRecipeFromOneUpload() async throws {
        let sim = SimulatedCamera()
        let cam = FujiCamera(transport: sim)
        let base = try await cam.uploadRAF(fakeRAF())
        XCTAssertEqual(base.asShotDR, 200)
        var neg = RecipeSettings(); neg.film = "Classic Neg."; neg.color = 4; neg.wbRed = 3; neg.dynamicRange = "DR400"; neg.normalize()
        var chrome = RecipeSettings(); chrome.film = "Classic Chrome"; chrome.wbBlue = -5; chrome.normalize()
        var acros = RecipeSettings(); acros.film = "Acros+G"; acros.normalize()
        let a = try await cam.render(neg, base: base)
        let b = try await cam.render(chrome, base: base)
        let c = try await cam.render(acros, base: base)
        XCTAssertEqual(sim.renders, 3)
        XCTAssertTrue(a.notes.contains { $0.contains("DR400") }, "DR above the photo's must be capped and said")
        XCTAssertTrue(b.notes.isEmpty)
        let pa = try pixel(a.jpeg), pb = try pixel(b.jpeg), pc = try pixel(c.jpeg)
        XCTAssertNotEqual(pa, pb)
        XCTAssertLessThan(abs(pc[0] - pc[1]) + abs(pc[1] - pc[2]), 8, "Acros renders grey")
        let again = try await cam.render(neg, base: base)
        XCTAssertEqual(try pixel(again.jpeg), pa, "same recipe, same render")
        let full = try await cam.render(neg, base: base, full: true)
        XCTAssertGreaterThan(full.jpeg.count, 0)
    }

    func testStudioRefusesOtherModelsAndNonRAWFiles() async throws {
        let cam = FujiCamera(transport: SimulatedCamera())
        do { _ = try await cam.uploadRAF(Data("not a raw".utf8)); XCTFail("non-RAF accepted") } catch {}
        do { _ = try await cam.uploadRAF(fakeRAF(model: "X-T5")); XCTFail("other model accepted") } catch {
            XCTAssertTrue("\(error)".contains("same camera model"))
        }
        let card = SimulatedCamera(); card.usbMode = nil
        do { _ = try await FujiCamera(transport: card).uploadRAF(fakeRAF()); XCTFail("card-reader mode accepted") } catch {}
    }

    /// FS1–FS3: the three-phase write (download, restore in a fresh session, read back) lands exactly, keeps the
    /// checksum valid and the other positions as they were; the WB shift is left as on the camera.
    func testWriteDialSlotEndToEnd() async throws {
        let sim = SimulatedCamera()
        let cam = FujiCamera(transport: sim)
        let before = try XCTUnwrap(SettingsFile.dialSlots(sim.settingsFile, model: "X-E5"))
        var r = RecipeSettings(); r.film = "Nostalgic Neg."; r.grainRoughness = "Weak"; r.grainSize = "Large"; r.dynamicRange = "DR400"
        r.highlight = -0.5; r.shadow = 2.5; r.color = 4; r.sharpness = -1; r.highIsoNr = -4; r.clarity = -3; r.wbRed = 2; r.normalize()
        let (report, prior) = try await cam.writeDialSlot(2, settings: r)
        XCTAssertTrue(report.ok, "\(report.mismatches)")
        XCTAssertEqual(report.unexpected, 0)
        XCTAssertEqual(prior.count, SettingsFile.xe5.size)
        let after = try XCTUnwrap(SettingsFile.dialSlots(sim.settingsFile, model: "X-E5"))
        XCTAssertEqual(after[2].settings.film, "Nostalgic Neg.")
        XCTAssertEqual(after[2].settings.shadow, 2.5)
        XCTAssertEqual(after[0].settings, before[0].settings)
        XCTAssertEqual(after[1].settings, before[1].settings)
        XCTAssertTrue(report.kept.contains("wb_red"))
        // Undo: writing the old FS3 back restores it.
        _ = try await cam.writeDialSlot(2, settings: before[2].settings)
        XCTAssertEqual(try XCTUnwrap(SettingsFile.dialSlots(sim.settingsFile, model: "X-E5"))[2].settings.film, before[2].settings.film)
    }

    /// The camera refuses a restore in the session that downloaded the file (why writeDialSlot resets the session).
    func testRestoreInTheSameSessionIsRefused() async throws {
        let sim = SimulatedCamera()
        let cam = FujiCamera(transport: sim)
        let file = try await cam.downloadSettingsBackup()
        do { try await cam.restoreSettingsFile(file); XCTFail("restore in the same session accepted") } catch {}
        await sim.resetSession()
        try await cam.restoreSettingsFile(file)
        var bad = file; bad[34760] = bad[34760] &+ 1   // checksum not moved
        await sim.resetSession()
        do { try await cam.restoreSettingsFile(bad); XCTFail("bad checksum accepted") } catch {}
    }

    /// DR200/DR400 need the slot's hidden ISO; a refused DR is reported, and the slot still matches its recipe.
    func testDynamicRangeGateAndMatching() async throws {
        let sim = SimulatedCamera()
        let cam = FujiCamera(transport: sim)
        var r = RecipeSettings(); r.film = "Classic Neg."; r.dynamicRange = "DR400"; r.color = 4; r.normalize()
        let refused = try await cam.writeBank(3, settings: r, name: "SOFT EMBER")
        XCTAssertTrue(refused.refused.contains { $0.field == "dynamicRange" })
        XCTAssertEqual(refused.after.dynamicRange, "DR100")
        XCTAssertEqual(r.cameraLimitedDifferences(refused.after)?.count, 1)
        sim.bankISO[3] = 640
        let ok = try await cam.writeBank(3, settings: r, name: "SOFT EMBER")
        XCTAssertTrue(ok.ok, "\(ok.refused) \(ok.mismatches)")
        XCTAssertEqual(ok.after.dynamicRange, "DR400")
    }
}

/// Match a look: measuring, learning from the library, and the camera search, all against the simulated camera.
final class MatchLookTests: XCTestCase {
    func fakeRAF() -> Data { Data("FUJIFILMCCD-RAW 0201FF383501X-E5".utf8) + Data(count: 4000) }
    func temp() -> Library { Library(root: FileManager.default.temporaryDirectory.appendingPathComponent("fuji-look-\(UUID().uuidString)")) }

    func recipe(_ film: String, red: Int = 0, blue: Int = 0, hi: Double = 0, sh: Double = 0, color: Int = 0) -> RecipeSettings {
        var s = RecipeSettings(); s.film = film; s.wbRed = red; s.wbBlue = blue; s.highlight = hi; s.shadow = sh; s.color = color
        s.normalize(); return s
    }

    /// The simulated camera's development of `s`, as the camera would hand it back.
    func developed(_ s: RecipeSettings) async throws -> Data {
        let cam = FujiCamera(transport: SimulatedCamera())
        let base = try await cam.uploadRAF(fakeRAF())
        return try await cam.render(s, base: base).jpeg
    }

    func testMeasuresWarmthMonoAndTrimsBorders() async throws {
        let neutral = try LookStats.measure(data: try await developed(recipe("Provia")))
        let warm = try LookStats.measure(data: try await developed(recipe("Provia", red: 6, blue: -6)))
        let mono = try LookStats.measure(data: try await developed(recipe("Acros")))
        XCTAssertGreaterThan(warm.castMid[1], neutral.castMid[1] + 3, "a warm WB shift reads as warmer near-greys")
        XCTAssertTrue(mono.mono); XCTAssertFalse(neutral.mono)
        XCTAssertEqual(neutral.distance(to: neutral), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(neutral.distance(to: warm), 5)

        // The same picture inside a white Instagram-style letterbox measures (almost) the same.
        let chromeJPEG = try await developed(recipe("Classic Chrome"))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(chromeJPEG as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let W = img.width, H = img.height * 2
        let ctx = try XCTUnwrap(CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.draw(img, in: CGRect(x: 0, y: img.height / 2, width: img.width, height: img.height))
        let boxed = LookStats.measure(image: try XCTUnwrap(ctx.makeImage()))
        let plain = LookStats.measure(image: img)
        XCTAssertLessThan(abs(boxed.tone[6] - plain.tone[6]), 3, "white borders are cut off before measuring")
    }

    /// The core promise: given only a photo developed with a recipe, the camera search finds that recipe (or one that
    /// looks the same) starting from a plain Provia guess.
    func testCameraSearchFindsAKnownRecipe() async throws {
        let target = recipe("Classic Neg.", red: 3, blue: -4, hi: -1, sh: 1, color: 2)
        let reference = try LookStats.measure(data: try await developed(target))
        let sim = SimulatedCamera()
        let cam = FujiCamera(transport: sim)
        let base = try await cam.uploadRAF(fakeRAF())
        var steps = 0
        let found = try await LookMatch.refine(reference: reference, start: recipe("Provia"), budget: 70,
                                               render: { try await cam.render($0, base: base).jpeg },
                                               progress: { _ in steps += 1 })
        let best = try XCTUnwrap(found.first)
        XCTAssertLessThanOrEqual(sim.renders, 70, "stays within the budget")
        XCTAssertEqual(steps, sim.renders)
        XCTAssertEqual(best.settings.film, "Classic Neg.")
        XCTAssertLessThanOrEqual(abs(best.settings.wbRed - 3), 1, best.settings.summary)
        XCTAssertLessThanOrEqual(abs(best.settings.wbBlue + 4), 1, best.settings.summary)
        XCTAssertLessThanOrEqual(abs((best.settings.color ?? 0) - 2), 1, best.settings.summary)
        XCTAssertGreaterThanOrEqual(best.match, 90, best.settings.summary)
        XCTAssertLessThanOrEqual(found.count, 3)
        XCTAssertTrue(sim.objectCount == 0, "every render is deleted from the camera")
    }

    func testCameraSearchStaysBlackAndWhite() async throws {
        var target = recipe("Acros+R"); target.monoWarmCool = 4; target.normalize()
        let reference = try LookStats.measure(data: try await developed(target))
        let guess = LookMatch.firstGuess(reference)
        XCTAssertTrue(guess.settings.isMonochrome)
        let cam = FujiCamera(transport: SimulatedCamera())
        let base = try await cam.uploadRAF(fakeRAF())
        let found = try await LookMatch.refine(reference: reference, start: guess.settings, budget: 30) { try await cam.render($0, base: base).jpeg }
        XCTAssertTrue(found.allSatisfy { $0.settings.isMonochrome })
        XCTAssertGreaterThan(try XCTUnwrap(found.first?.settings.monoWarmCool), 0, "warm toning found")
    }

    /// The first guess learns from the library's sample photos: a new photo with a look close to one recipe's samples
    /// gets that recipe's film and settings, and the evaluation reports how well that works.
    func testFirstGuessLearnsFromLibrarySamples() async throws {
        let lib = temp()
        let looks: [(String, RecipeSettings)] = [
            ("Warm Neg", recipe("Classic Neg.", red: 4, blue: -5, hi: -1, color: 3)),
            ("Cool Chrome", recipe("Classic Chrome", red: -2, blue: 3, sh: 1, color: -2)),
            ("Bright Velvia", recipe("Velvia", color: 3)),
            ("Soft Eterna", recipe("Eterna", hi: -2, sh: -2)),
            ("Golden Nostalgic", recipe("Nostalgic Neg.", red: 5, blue: -6, color: 1)),
            ("Plain Provia", recipe("Provia")),
        ]
        for (name, s) in looks {
            let r = try lib.save(Recipe(slug: "", name: name, settings: s))
            let dir = lib.root.appendingPathComponent("samples/\(r.slug)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // three photos each: the recipe and two near variations (a different light, a slightly different exposure)
            for (i, v) in [s, { var x = s; x.wbRed += 1; return x }(), { var x = s; x.highlight += 0.5; return x }()].enumerated() {
                try await developed(v).write(to: dir.appendingPathComponent("\(i).jpg"))
            }
        }
        let index = LookIndex.load(lib)
        XCTAssertEqual(index.entries.count, 18)
        XCTAssertEqual(LookIndex.load(lib).entries.count, 18, "a second load reuses the measurements")

        let photo = try LookStats.measure(data: try await developed(recipe("Classic Neg.", red: 4, blue: -4, hi: -1, color: 3)))
        let guess = LookMatch.firstGuess(photo, index: index, recipes: try lib.recipes())
        XCTAssertEqual(guess.neighbours.first?.recipe.name, "Warm Neg")
        XCTAssertEqual(guess.settings.film, "Classic Neg.")
        XCTAssertGreaterThan(guess.settings.wbRed, 1)

        let ev = LookMatch.evaluate(index: index, recipes: try lib.recipes())
        XCTAssertEqual(ev.photos, 18); XCTAssertEqual(ev.recipes, 6)
        XCTAssertGreaterThanOrEqual(ev.recognisedTop3, 0.8, ev.text)
        XCTAssertEqual(ev.mono, 1, accuracy: 1e-9)
        XCTAssertTrue(ev.text.contains("18 sample photos of 6 recipes"), ev.text)
    }

    func testSavingAMatchKeepsTheReferenceAndAvoidsDuplicates() throws {
        let lib = temp()
        let ref = lib.root.appendingPathComponent("leica.jpg")
        try FileManager.default.createDirectory(at: lib.root, withIntermediateDirectories: true)
        try SimulatedCamera.renderJPEG(ConversionProfile(Data(count: ConversionProfile.base + 4 * 29)), full: true).write(to: ref)
        let s = recipe("Classic Chrome", red: 2, blue: -3)
        let first = try lib.saveMatched(s, name: "Leica Look", reference: ref, raw: nil, notes: ["note"])
        XCTAssertFalse(first.existing)
        XCTAssertEqual(first.recipe.status, "to-try")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lib.root.appendingPathComponent("samples/leica-look/reference.jpg").path))
        XCTAssertTrue(first.recipe.notes?.contains("not checked on the camera") == true)
        let again = try lib.saveMatched(s, name: "Leica Look 2", reference: ref)
        XCTAssertTrue(again.existing); XCTAssertEqual(again.recipe.slug, "leica-look")
        XCTAssertTrue(LookIndex.photos(first.recipe, library: lib).isEmpty, "the reference photo isn't a sample of the recipe")
    }
}
