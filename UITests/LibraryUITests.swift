import XCTest

/// Library tab and the logger's Library picker: pinned sections, letter index, ranked search.
@MainActor
final class LibraryUITests: HarnessTestCase {
  /// Same rule as `TimeSlot`: morning 05–10, midday 11–16, evening otherwise.
  var usualHeader: String {
    switch Calendar.current.component(.hour, from: .now) {
    case 5..<11: "Usual in the morning"
    case 11..<17: "Usual at midday"
    default: "Usual in the evening"
    }
  }

  func header(_ text: String) -> XCUIElement { app.staticTexts[text].firstMatch }
  /// The names sorted by where their first row sits on screen.
  func onScreenOrder(_ names: [String]) -> [String] {
    names.sorted {
      app.staticTexts[$0].firstMatch.frame.minY < app.staticTexts[$1].firstMatch.frame.minY
    }
  }

  func search(_ text: String) {
    let field = app.searchFields.firstMatch
    if !field.exists { app.swipeDown() }
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText(text)
  }

  func testLibraryShowsPinnedSectionsInOrderThenLetters() {
    launch("libraryTab")
    XCTAssertTrue(header(usualHeader).waitForExistence(timeout: 10))
    let order = [usualHeader, "Favorites", "Recent"].map { header($0).frame.minY }
    XCTAssertEqual(order, order.sorted(), "sections out of order: \(order)")
    // Usual: most logged first. Each item shows once among the pinned sections.
    let usual = ["Greek yogurt", "Flat white", "Banana"]
    XCTAssertEqual(onScreenOrder(usual), usual)
    XCTAssertLessThan(
      app.staticTexts["Banana"].firstMatch.frame.maxY, header("Favorites").frame.minY)
    capture("library-light")
    // A compact phone does not materialize the offscreen letter section yet.
    if !header("A").exists { app.swipeUp() }
    XCTAssertTrue(header("A").waitForExistence(timeout: 5))
    capture("library-letters")
    launch("libraryTab", dark: true)
    XCTAssertTrue(header(usualHeader).waitForExistence(timeout: 10))
    capture("library-dark")
    launch("libraryTab", large: true)
    XCTAssertTrue(header(usualHeader).waitForExistence(timeout: 10))
    capture("library-large-text")
  }

  func testLetterIndexJumpsToSection() {
    launch("libraryTab")
    XCTAssertTrue(header(usualHeader).waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Zucchini"].isHittable)
    // The index is the trailing strip; its letters are spread over its height.
    let index =
      app.otherElements["Section index"].exists
      ? app.otherElements["Section index"] : app.descendants(matching: .any)["Section index"]
    if index.exists {
      index.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap()
    } else {
      let window = app.windows.firstMatch
      window.coordinate(withNormalizedOffset: CGVector(dx: 0.985, dy: 0.86)).tap()
    }
    XCTAssertTrue(app.staticTexts["Zucchini"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Zucchini"].isHittable, "index did not jump near Z")
    capture("library-index-jump")
  }

  func testSearchRanksMatchesAndToleratesOneTypo() {
    launch("libraryTab")
    XCTAssertTrue(header(usualHeader).waitForExistence(timeout: 10))
    search("yog")
    XCTAssertTrue(app.staticTexts["Yogurt parfait"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Greek yogurt"].exists)
    XCTAssertEqual(
      onScreenOrder(["Greek yogurt", "Yogurt parfait"]), ["Yogurt parfait", "Greek yogurt"])
    XCTAssertFalse(app.staticTexts["Banana"].exists, "non-matching rows hide")
    XCTAssertFalse(header(usualHeader).exists, "sections hide while searching")
    capture("library-search")
    app.searchFields.firstMatch.buttons["Clear text"].tap()
    search("chiken")
    XCTAssertTrue(app.staticTexts["Chicken breast"].waitForExistence(timeout: 3))
  }

  func testPickerAddsItemFoundBySearch() {
    launch("entry")
    XCTAssertTrue(app.buttons["attachLibrary"].waitForExistence(timeout: 10))
    app.buttons["attachLibrary"].tap()
    XCTAssertTrue(header(usualHeader).waitForExistence(timeout: 5))
    search("parfait")
    app.staticTexts["Yogurt parfait"].firstMatch.tap()
    let add = app.buttons["addSelected"]
    XCTAssertTrue(add.waitForExistence(timeout: 3))
    XCTAssertTrue(add.isHittable, "Add stays reachable while search is open")
    capture("picker-search-selected")
    add.tap()
    XCTAssertTrue(app.staticTexts["Yogurt parfait"].waitForExistence(timeout: 5))
  }

  func testPickerAddsUsualItemAndOffersAIForUnknownFood() {
    launch("entry")
    XCTAssertTrue(app.buttons["attachLibrary"].waitForExistence(timeout: 10))
    app.buttons["attachLibrary"].tap()
    XCTAssertTrue(header(usualHeader).waitForExistence(timeout: 5))
    capture("picker-empty")
    app.staticTexts["Greek yogurt"].firstMatch.tap()
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add 1 item'")).firstMatch
        .waitForExistence(timeout: 3))
    capture("picker-selected")
    search("dragon fruit")
    let describe = app.buttons["describeWithAI"]
    XCTAssertTrue(describe.waitForExistence(timeout: 3))
    capture("picker-no-match")
    describe.tap()
    let field =
      app.textViews["mealText"].exists ? app.textViews["mealText"] : app.textFields["mealText"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertTrue((field.value as? String ?? "").contains("dragon fruit"))
    capture("picker-describe-result")
  }
}
