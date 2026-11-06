import XCTest

/// Millilitre portions for drinks (PET-114). The live AI backend is not covered here.
@MainActor
final class DrinkUnitsUITests: HarnessTestCase {
  func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
  func header(_ text: String) -> XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch
  }

  func testReviewShowsAndEditsMillilitres() {
    launch("drink")
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 10))
    let portion = app.textFields["Portion of Beer in millilitres"]
    XCTAssertTrue(portion.exists)
    XCTAssertEqual(portion.value as? String, "330")
    XCTAssertTrue(app.staticTexts["ml"].exists)
    XCTAssertTrue(element("reviewTotal").label.contains("142 kcal"))

    app.buttons["Increase Portion of Beer in millilitres"].tap()
    XCTAssertEqual(portion.value as? String, "335")
    XCTAssertTrue(element("reviewTotal").label.contains("144 kcal"))

    app.buttons["foodRow0"].tap()
    XCTAssertTrue(app.staticTexts["Per 100 ml"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["335 ml"].exists)
    XCTAssertEqual(app.textFields["per100g-calories0"].value as? String, "43")
    capture("drink-review-light")

    launch("drink", dark: true)
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 10))
    app.buttons["foodRow0"].tap()
    capture("drink-review-dark")

    launch("drink", large: true)
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 10))
    app.buttons["foodRow0"].tap()
    XCTAssertTrue(app.staticTexts["per 100 ml"].firstMatch.waitForExistence(timeout: 5))
    capture("drink-review-large-text")
  }

  func testFoodEditorOffersPer100ml() {
    launch("drinkFoodEditor")
    let picker = app.segmentedControls["foodUnitPicker"]
    XCTAssertTrue(picker.waitForExistence(timeout: 10))
    XCTAssertTrue(picker.buttons["Per serving"].isSelected)
    let serving = app.textFields["servingSizeField"]
    XCTAssertTrue(serving.exists)
    XCTAssertEqual(serving.value as? String, "250")
    XCTAssertTrue(app.buttons["servingUnitPicker"].exists)
    XCTAssertTrue(header("Nutrition per 100 ml").exists)
    capture("drink-editor-serving-light")
    picker.buttons["Per 100 ml"].tap()
    XCTAssertTrue(picker.buttons["Per 100 ml"].isSelected)
    XCTAssertFalse(serving.exists)
    XCTAssertTrue(header("Nutrition per 100 ml").exists)
    capture("drink-editor-per100ml-light")
    picker.buttons["Per 100 g"].tap()
    XCTAssertTrue(header("Nutrition per 100 g").exists)

    launch("drinkFoodEditor", dark: true)
    XCTAssertTrue(app.segmentedControls["foodUnitPicker"].waitForExistence(timeout: 10))
    capture("drink-editor-dark")
    launch("drinkFoodEditor", large: true)
    XCTAssertTrue(app.segmentedControls["foodUnitPicker"].waitForExistence(timeout: 10))
    capture("drink-editor-large-text")
  }

  func testQuickLogUsesMillilitres() {
    launch("drinkQuickLog")
    let quantity = app.textFields["Quantity of Oat drink in millilitres"]
    XCTAssertTrue(quantity.waitForExistence(timeout: 10))
    XCTAssertEqual(quantity.value as? String, "250")
    XCTAssertTrue(app.staticTexts["115 kcal"].exists)
    capture("drink-quicklog-light")
    launch("drinkQuickLog", dark: true)
    XCTAssertTrue(quantity.waitForExistence(timeout: 10))
    capture("drink-quicklog-dark")
    launch("drinkQuickLog", large: true)
    XCTAssertTrue(quantity.waitForExistence(timeout: 10))
    capture("drink-quicklog-large-text")
  }
}
