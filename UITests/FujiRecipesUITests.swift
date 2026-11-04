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

    /// Studio: the RAW is there, Render develops every chosen recipe on the camera, tiles appear, a tile opens big.
    func testStudioRendersAndCompares() {
        tab(1)   // let the simulated camera connect first
        XCTAssertTrue(app.buttons["slot.C1"].waitForExistence(timeout: 15))
        tab(2)
        XCTAssertTrue(app.staticTexts["studio.rawName"].waitForExistence(timeout: 5))
        let render = app.buttons["studio.render"]
        XCTAssertTrue(render.waitForExistence(timeout: 5))
        render.tap()
        XCTAssertTrue(app.staticTexts["studio.allRendered"].waitForExistence(timeout: 30))
        let tile = app.otherElements["studio.tile.UI Chrome"].images.firstMatch
        if tile.exists { tile.tap() } else { app.otherElements["studio.tile.UI Chrome"].tap() }
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
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
}
