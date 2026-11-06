import XCTest

/// Logger and Today flows. Launch scenarios are in `LoggerFixtures.state`.
@MainActor
final class LoggerUITests: HarnessTestCase {
  override func launch(_ scenario: String = "review", dark: Bool = false, large: Bool = false) {
    super.launch(scenario, dark: dark, large: large)
    if scenario == "today" || scenario == "libraryTab" { return }
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 10))
  }

  func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
  func per100g(_ macro: String, _ index: Int = 0) -> XCUIElement {
    app.textFields["per100g-\(macro)\(index)"]
  }
  func hideKeyboard() { app.buttons["Hide keyboard"].tap() }
  func replace(_ field: XCUIElement, with text: String) {
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    let old = field.value as? String ?? ""
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
  }

  func testSingleFoodShowsNutritionAndDayBalance() {
    launch()
    XCTAssertEqual(app.buttons["loggerPrimary"].label, "Log meal")
    XCTAssertFalse(per100g("calories").exists)
    app.buttons["foodRow0"].tap()
    XCTAssertTrue(per100g("calories").waitForExistence(timeout: 5))
    XCTAssertEqual(per100g("calories").value as? String, "165")
    XCTAssertEqual(per100g("protein").value as? String, "31")
    XCTAssertTrue(element("reviewTotal").label.contains("165 kcal"))
    XCTAssertTrue(app.staticTexts["Calories after this meal"].exists)
    XCTAssertTrue(app.buttons["loggerPrimary"].isHittable)
    XCTAssertFalse(app.textFields["mealText"].exists)
    capture("review-light")
    launch(dark: true)
    capture("review-dark")
    launch(large: true)
    capture("review-large-text")
  }

  func testGramsEditUpdatesTotalsInPlace() {
    launch()
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Increase Portion'")).firstMatch
      .tap()
    XCTAssertTrue(element("reviewTotal").label.contains("173 kcal"))
    let grams = app.textFields.matching(NSPredicate(format: "label BEGINSWITH 'Portion of'"))
      .firstMatch
    replace(grams, with: "200")
    XCTAssertTrue(element("reviewTotal").label.contains("330 kcal"))
    capture("grams-keyboard")
    hideKeyboard()
    XCTAssertEqual(grams.value as? String, "200")
    XCTAssertTrue(element("reviewTotal").label.contains("330 kcal"))
  }

  func testPer100gEditUpdatesPortion() {
    launch()
    app.buttons["foodRow0"].tap()
    replace(per100g("calories"), with: "200")
    XCTAssertTrue(element("reviewTotal").label.contains("200 kcal"))
    hideKeyboard()
    XCTAssertEqual(per100g("calories").value as? String, "200")
    replace(per100g("protein"), with: "25")
    hideKeyboard()
    XCTAssertEqual(per100g("protein").value as? String, "25")
    XCTAssertTrue(app.staticTexts["25 g"].exists)
  }

  func testMultipleFoodsExpandOneAtATimeAndRemove() {
    launch("multiple")
    XCTAssertTrue(element("reviewTotal").label.contains("459 kcal"))
    XCTAssertFalse(per100g("calories", 0).exists)
    capture("multiple-collapsed")
    app.buttons["foodRow1"].tap()
    XCTAssertTrue(per100g("calories", 1).waitForExistence(timeout: 5))
    XCTAssertEqual(per100g("calories", 1).value as? String, "130")
    capture("multiple-expanded")
    app.buttons["foodRow0"].tap()
    XCTAssertTrue(per100g("calories", 0).waitForExistence(timeout: 5))
    XCTAssertFalse(per100g("calories", 1).exists)
    app.swipeUp()
    app.buttons["foodRow2"].tap()
    app.swipeUp()
    app.buttons["removeFood2"].tap()
    app.buttons["Remove food"].tap()
    XCTAssertFalse(app.buttons["foodRow2"].waitForExistence(timeout: 2))
    XCTAssertTrue(element("reviewTotal").label.contains("399 kcal"))
  }

  func testLabelShowsPer100gValues() {
    launch("label")
    app.buttons["foodRow0"].tap()
    XCTAssertTrue(per100g("calories").waitForExistence(timeout: 5))
    XCTAssertEqual(per100g("calories").value as? String, "442")
    XCTAssertTrue(app.staticTexts["From label"].exists)
    XCTAssertTrue(element("reviewTotal").label.contains("221 kcal"))
    capture("label")
  }

  func testEntryShowsThreeSourcesAndEstimates() {
    launch("entry")
    XCTAssertTrue(app.buttons["attachCamera"].exists)
    XCTAssertTrue(app.buttons["attachScan"].exists)
    XCTAssertTrue(app.buttons["attachLibrary"].exists)
    XCTAssertTrue(app.buttons["attachPhotos"].exists)
    XCTAssertFalse(app.buttons["loggerPrimary"].isEnabled)
    capture("entry-light")
    let field =
      app.textFields["mealText"].exists ? app.textFields["mealText"] : app.textViews["mealText"]
    field.tap()
    field.typeText("Chicken breast 100 g")
    XCTAssertTrue(app.buttons["loggerPrimary"].isEnabled)
    capture("entry-keyboard")
    app.buttons["loggerPrimary"].tap()
    XCTAssertTrue(app.buttons["foodRow0"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["loggerPrimary"].label, "Log meal")
  }

  func testOptionalClarificationFailureAndRecovery() {
    launch("failure")
    XCTAssertTrue(app.buttons["loggerPrimary"].isEnabled)
    app.buttons["adjustFood0"].firstMatch.tap()
    XCTAssertTrue(app.buttons["updateEstimate"].waitForExistence(timeout: 5))
    app.buttons["Cooked"].tap()
    app.buttons["updateEstimate"].tap()
    XCTAssertTrue(app.buttons["restoreEstimate"].waitForExistence(timeout: 10))
    app.buttons["restoreEstimate"].tap()
    XCTAssertTrue(app.buttons["foodRow0"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["loggerPrimary"].label, "Log meal")
    app.buttons["loggerPrimary"].tap()
    XCTAssertTrue(app.buttons["Save to Library"].waitForExistence(timeout: 5))
  }

  func testAddFoodReturnsToEntryAndBack() {
    launch("multiple")
    app.buttons["addFood"].tap()
    XCTAssertTrue(app.buttons["attachPhotos"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["loggerPrimary"].label, "Review meal")
    app.buttons["loggerPrimary"].tap()
    XCTAssertTrue(app.buttons["foodRow0"].waitForExistence(timeout: 5))
    XCTAssertTrue(element("reviewTotal").label.contains("459 kcal"))
  }

  func title(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
  }

  func testTodayCalendarChangesDayAndSwipeDoesNot() {
    launch("today")
    let day: TimeInterval = 86_400
    XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Protein"].firstMatch.waitForExistence(timeout: 10))
    app.swipeRight()
    XCTAssertTrue(app.navigationBars["Today"].exists, "swipe keeps today")
    app.buttons["Choose day"].tap()
    XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 3))
    capture("today-calendar")
    let yesterday = (Date.now - day).formatted(.dateTime.weekday(.wide).month(.wide).day())
    app.datePickers.firstMatch.buttons[yesterday].tap()
    XCTAssertTrue(app.navigationBars[title(.now - day)].waitForExistence(timeout: 3), "picked day")
    XCTAssertTrue(app.staticTexts["Protein"].firstMatch.waitForExistence(timeout: 10))
    capture("today-yesterday")
    app.swipeLeft()
    XCTAssertTrue(app.navigationBars[title(.now - day)].exists, "swipe keeps the picked day")
    app.buttons["Today"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3), "back to today")
  }

  func testLibraryItemCanBeFavoritedAndEdited() {
    launch("libraryTab")
    let yogurt = app.staticTexts["Greek yogurt"].firstMatch
    XCTAssertTrue(yogurt.waitForExistence(timeout: 10))
    yogurt.tap()
    let favorite = app.buttons["favoriteButton"]
    XCTAssertTrue(favorite.waitForExistence(timeout: 5))
    XCTAssertEqual(favorite.label, "Favorite")
    favorite.tap()
    XCTAssertEqual(favorite.label, "Unfavorite")
    capture("library-quicklog-favorite")
    app.buttons["editButton"].tap()
    XCTAssertTrue(app.navigationBars["Edit food"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(favorite.waitForExistence(timeout: 5))
    app.buttons["Close"].firstMatch.tap()
    let row = app.cells.containing(.staticText, identifier: "Greek yogurt").firstMatch
    XCTAssertTrue(row.images["Favorite"].waitForExistence(timeout: 3))
  }

  func testMealIngredientsExpandSheetToLarge() {
    launch("libraryTab")
    // The meal sits under "O", below the first screen.
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 10))
    search.tap()
    search.typeText("overnight")
    let meal = app.staticTexts["Overnight oats"].firstMatch
    XCTAssertTrue(meal.waitForExistence(timeout: 10))
    meal.tap()
    let ingredients = app.buttons["Ingredients"].firstMatch
    XCTAssertTrue(ingredients.waitForExistence(timeout: 5))
    let mediumTop = app.navigationBars["Overnight oats"].frame.minY
    ingredients.tap()
    XCTAssertTrue(app.staticTexts["Ingredient 1"].waitForExistence(timeout: 5))
    sleep(1)
    XCTAssertLessThan(app.navigationBars["Overnight oats"].frame.minY, mediumTop - 200)
    XCTAssertTrue(app.staticTexts["Ingredient 1"].isHittable)
    capture("library-meal-ingredients")
    app.buttons["editButton"].tap()
    XCTAssertTrue(app.navigationBars["Edit meal"].waitForExistence(timeout: 5))
  }
}
