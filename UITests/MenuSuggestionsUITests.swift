import XCTest

/// Eat out on the Suggestions tab: menu photos in, five dishes out, + fills the logger.
/// Scenarios "suggestionsMenu…" leave 650 kcal, 40 g protein, 70 g carbs, 20 g fat of
/// 2,000 / 120 / 200 / 70, with two fixture menu pages.
@MainActor
final class MenuSuggestionsUITests: HarnessTestCase {
  func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

  func testSwitchingToEatOutSwapsPrepTimeForMenuPhotos() {
    launch("suggestions")
    XCTAssertTrue(app.buttons["getSuggestions"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.steppers.firstMatch.exists)
    app.buttons["Eat out"].tap()
    XCTAssertTrue(element("addMenuPage").waitForExistence(timeout: 5))
    XCTAssertFalse(app.steppers.firstMatch.exists)
    // No menu photo yet, so there is nothing to suggest from.
    XCTAssertFalse(app.buttons["getMenuSuggestions"].isEnabled)
    app.buttons["Cook"].tap()
    XCTAssertTrue(app.steppers.firstMatch.waitForExistence(timeout: 5))
  }

  func testEmptyEatOutInAllAppearances() {
    for variant in ["light", "dark", "large-text"] {
      launch("suggestionsMenuEmpty", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(element("addMenuPage").waitForExistence(timeout: 10))
      XCTAssertFalse(app.buttons["getMenuSuggestions"].isEnabled)
      capture("menu-empty-\(variant)")
    }
  }

  func testFiveDishesShowWhatEachLeavesAndPlusFillsTheLogger() {
    launch("suggestionsMenu")
    XCTAssertTrue(element("addMenuPage").waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons.matching(identifier: "removeMenuPage").count, 2)
    capture("menu-pages-light")
    app.buttons["getMenuSuggestions"].tap()
    let plus = app.buttons.matching(identifier: "logMenuDish")
    XCTAssertTrue(plus.firstMatch.waitForExistence(timeout: 10))
    XCTAssertEqual(plus.count, 5)
    // Each row reads as one element: name, kcal, macros, what it leaves, and the tip.
    let rows = app.staticTexts.matching(identifier: "menuDishImpact")
    func row(_ index: Int, contains text: String) {
      let label = rows.element(boundBy: index).label
      XCTAssertTrue(label.contains(text), label)
    }
    row(0, contains: "Leaves 130 kcal · Protein goal reached · Fat 8 g over")
    row(0, contains: "Ask for the dressing on the side.")
    row(2, contains: "Leaves 340 kcal · 32 g protein to go")
    row(3, contains: "330 kcal over · Protein 12 g over · Carbs goal reached · Fat 34 g over")
    capture("menu-results-light")
    app.swipeUp()
    capture("menu-results-light-scrolled")

    let soup = app.buttons["Log Tomato soup"]
    if !soup.isHittable { app.swipeUp() }
    soup.tap()
    XCTAssertTrue(element("loggerPrefill").waitForExistence(timeout: 5))
    XCTAssertEqual(
      element("loggerPrefill").label,
      "Tomato soup (restaurant): A bowl of soup with bread, about 400 ml.")
  }

  func testResultsInDarkAndLargeText() {
    for variant in ["dark", "large-text"] {
      launch("suggestionsMenu", dark: variant == "dark", large: variant == "large-text")
      let get = app.buttons["getMenuSuggestions"]
      XCTAssertTrue(get.waitForExistence(timeout: 10))
      capture("menu-pages-\(variant)")
      if !get.isHittable { app.swipeUp() }
      get.tap()
      XCTAssertTrue(
        app.buttons.matching(identifier: "logMenuDish").firstMatch.waitForExistence(timeout: 10))
      capture("menu-results-\(variant)")
      app.swipeUp()
      capture("menu-results-\(variant)-scrolled")
    }
  }

  func testRemovingAPageKeepsTheOther() {
    launch("suggestionsMenu")
    let remove = app.buttons.matching(identifier: "removeMenuPage")
    XCTAssertTrue(remove.firstMatch.waitForExistence(timeout: 10))
    remove.firstMatch.tap()
    XCTAssertEqual(remove.count, 1)
    XCTAssertTrue(app.buttons["getMenuSuggestions"].isEnabled)
    remove.firstMatch.tap()
    XCTAssertEqual(remove.count, 0)
    XCTAssertFalse(app.buttons["getMenuSuggestions"].isEnabled)
  }

  func testLoadingAndFailure() {
    launch("suggestionsMenuLoading")
    let get = app.buttons["getMenuSuggestions"]
    XCTAssertTrue(get.waitForExistence(timeout: 10))
    get.tap()
    XCTAssertFalse(get.isEnabled)
    capture("menu-loading")
    XCTAssertTrue(
      app.buttons.matching(identifier: "logMenuDish").firstMatch.waitForExistence(timeout: 10))

    launch("suggestionsMenuFailure")
    XCTAssertTrue(get.waitForExistence(timeout: 10))
    get.tap()
    XCTAssertTrue(
      app.staticTexts["Couldn't read the menu. Try a clearer photo."].waitForExistence(timeout: 5))
    XCTAssertTrue(get.isEnabled)
    capture("menu-failure")
  }
}
