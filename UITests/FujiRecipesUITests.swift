import XCTest

/// The iPhone app end to end, as the owner uses it, against a throwaway library and the simulated X-E5
/// (`-uiTesting`, see AppModel.uiTestLibrary). Nothing touches real photos or a real camera.
final class FujiRecipesUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    func tab(_ i: Int) { app.tabBars.buttons.element(boundBy: i).tap() }

    /// Recipes: the library shows; a card opens its page; a rename is saved and shows on the card.
    func testRecipesOpenAndRename() {
        let card = app.staticTexts["UI Chrome"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["UI Acros"].exists)
        card.tap()
        let name = app.textFields["recipe.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" Two")
        app.buttons["recipe.save"].tap()
        XCTAssertTrue(app.staticTexts["UI Chrome Two"].waitForExistence(timeout: 5))
    }

    /// Camera: the simulated X-E5 connects; a recipe put in C3 is written at once; Undo puts the slot back.
    func testPutInSlotAndUndo() {
        tab(1)
        let c3 = app.buttons["slot.C3"]
        XCTAssertTrue(c3.waitForExistence(timeout: 15))
        c3.tap()
        let pick = app.buttons.containing(NSPredicate(format: "label CONTAINS 'UI Neg'")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()
        let toast = app.staticTexts["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10))
        XCTAssertTrue(toast.label.contains("UI Neg in C3"), toast.label)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'c3: ui neg'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'c3: empty'")).firstMatch.waitForExistence(timeout: 10))
    }

    /// Studio: with the camera connected it renders every chosen recipe by itself, tiles appear, a recipe can be
    /// picked for this photo (and the Picked filter shows it), a tile opens big with Pick there too.
    func testStudioRendersAndCompares() {
        tab(1)   // let the simulated camera connect first
        XCTAssertTrue(app.buttons["slot.C1"].waitForExistence(timeout: 15))
        tab(2)
        XCTAssertTrue(app.staticTexts["studio.rawName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["studio.allRendered"].waitForExistence(timeout: 40))   // no button press
        let pick = app.buttons["studio.pick.UI Chrome"]
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()
        XCTAssertTrue(app.buttons["Picked 1"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["studio.photo.UI Chrome"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["preview.pick"].exists)
    }

    /// No camera (the research renders hold it, or it isn't plugged in): the big preview still gets sharp, from the RAW's
    /// own preview, and says full size needs the camera.
    func testPreviewSharpWithoutCamera() {
        app.terminate()
        app.launchArguments = ["-uiTesting", "-noCamera"]
        app.launch()
        tab(2)
        let card = app.descendants(matching: .any)["studio.photo.UI Chrome"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "sharp"), object: card)], timeout: 15)   // the card itself is sharp
        card.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        let quality = app.staticTexts["preview.quality"]
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
        let sharp = NSPredicate(format: "label == %@", "Detail from the RAW · full size needs the camera")
        wait(for: [XCTNSPredicateExpectation(predicate: sharp, object: quality)], timeout: 10)
    }

    /// Studio ▸ Paste: a copied photo becomes the look to match (and switches to Match a look); a copied RAF becomes
    /// the Studio's RAW.
    func testStudioPaste() {
        tab(2)
        XCTAssertTrue(app.staticTexts["studio.rawName"].waitForExistence(timeout: 10))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 40)).image { c in
            UIColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
        }
        UIPasteboard.general.image = image
        let paste = app.buttons["studio.paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        let ref = app.staticTexts["look.referenceName"]
        XCTAssertTrue(ref.waitForExistence(timeout: 10))
        XCTAssertTrue(ref.label.hasPrefix("Pasted "), ref.label)

        // A RAF copied in Files: the camera's RAW type on the clipboard.
        var raf = Data("FUJIFILMCCD-RAW 0201FF129502".utf8); raf.append(Data(count: 4096))
        UIPasteboard.general.setData(raf, forPasteboardType: "com.fuji.raw-image")
        app.buttons["studio.mode.recipes"].tap()
        let paste2 = app.buttons["studio.paste"]
        XCTAssertTrue(paste2.waitForExistence(timeout: 5))
        paste2.tap()
        let toast = app.staticTexts["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10))
        XCTAssertTrue(toast.label.contains("develops this RAW"), toast.label)
    }

    /// Camera → library: on connect the simulated X-E5's slot recipes that the library doesn't have are added as
    /// the owner's own ("Green Acros" from C1's name), with Undo in the toast.
    func testCameraRecipesJoinLibrary() {
        app.terminate()
        app.launchArguments = ["-uiTesting", "-syncSlots", "YES"]
        app.launch()
        let toast = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'from your camera'")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 20))
        XCTAssertTrue(toast.label.contains("Green Acros"), toast.label)
        XCTAssertTrue(app.staticTexts["Green Acros"].waitForExistence(timeout: 5))
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Removed what was added'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Green Acros"].exists)
    }

    /// Clarity (slows saving): off by default, so UI Neg (Clarity −2) goes to C3 with 0. Turning it on asks first
    /// ("No" keeps it off); "Yes" gives C3 its −2 back, and off sets it to 0 again.
    func testClaritySwitch() {
        tab(1)
        let c3 = app.buttons["slot.C3"]
        XCTAssertTrue(c3.waitForExistence(timeout: 15))
        // The list redraws once the simulated camera has connected; tap after it settles.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Provia defaults'")).firstMatch.waitForExistence(timeout: 15))
        c3.tap()
        let pick = app.buttons.containing(NSPredicate(format: "label CONTAINS 'UI Neg'")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()
        XCTAssertTrue(app.staticTexts["toast"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Clarity 0 on the camera'")).firstMatch.waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()

        let clarity = app.switches["camera.clarity"]
        for _ in 0..<4 where !clarity.isHittable { app.swipeUp() }
        XCTAssertEqual(clarity.value as? String, "0")
        clarity.switches.firstMatch.tap()
        let ask = app.alerts["Turn on Clarity?"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.buttons["No"].tap()
        XCTAssertEqual(clarity.value as? String, "0")

        clarity.switches.firstMatch.tap()
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.buttons["Yes, Turn On"].tap()
        let on = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'C3 get their recipe'")).firstMatch
        XCTAssertTrue(on.waitForExistence(timeout: 15))
        XCTAssertEqual(clarity.value as? String, "1")

        clarity.switches.firstMatch.tap()      // off: no question
        let off = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'C3 set to 0'")).firstMatch
        XCTAssertTrue(off.waitForExistence(timeout: 15))
        XCTAssertEqual(clarity.value as? String, "0")
    }

    /// Add recipes: pasted links are queued; the same link twice isn't.
    func testAddRecipeLinks() {
        tab(3)
        let field = app.textFields["add.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("https://www.instagram.com/reel/UITEST1/ https://www.instagram.com/reel/UITEST2/")
        app.buttons["add.button"].tap()
        XCTAssertTrue(app.staticTexts["toast"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'UITEST2'")).firstMatch.waitForExistence(timeout: 5))
    }

    /// Match a look: the reference photo is read, the library suggests a first guess, the (simulated) camera searches,
    /// and the closest result is saved as a to-try recipe that then shows up in Recipes.
    func testMatchALook() {
        tab(1)   // let the simulated camera connect first
        XCTAssertTrue(app.buttons["slot.C1"].waitForExistence(timeout: 15))
        tab(2)
        let mode = app.buttons["studio.mode.look"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.tap()
        XCTAssertTrue(app.staticTexts["look.referenceName"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["look.guess"].waitForExistence(timeout: 20), "a first guess appears without the camera")
        let refine = app.buttons["look.refine"]
        XCTAssertTrue(refine.waitForExistence(timeout: 5))
        refine.tap()
        let save = app.buttons["look.save.0"]
        XCTAssertTrue(save.waitForExistence(timeout: 90), "the camera search finishes with results")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '% match'")).firstMatch.exists)
        save.tap()
        XCTAssertTrue(app.buttons["look.save.0.done"].waitForExistence(timeout: 5), "saved")
        tab(0)
        XCTAssertTrue(app.staticTexts["Look of Leica street"].waitForExistence(timeout: 5), "the saved look is in the library")
    }
}
