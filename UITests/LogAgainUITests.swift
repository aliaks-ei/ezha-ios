import XCTest

/// "Log again" sheet (PET-107): pick the day, change the amounts, then log a copy.
@MainActor
final class LogAgainUITests: HarnessTestCase {
  /// "Chicken rice bowl": one item, 250 g, 520 kcal.
  private let fieldName = "Portion of Chicken rice bowl in grams"

  func testAppearances() {
    for variant in ["light", "dark", "large-text"] {
      launch("logAgain", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.buttons["logAgainButton"].waitForExistence(timeout: 10))
      XCTAssertEqual(app.buttons["logAgainButton"].label, "Log to Today")
      XCTAssertTrue(app.textFields[fieldName].exists)
      capture("log-again-\(variant)")
    }
  }

  func testKeyboardDoesNotCoverField() {
    for variant in ["light", "large-text"] {
      launch("logAgain", large: variant == "large-text")
      let field = app.textFields[fieldName]
      XCTAssertTrue(field.waitForExistence(timeout: 10))
      field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
      let keyboard = app.keyboards.firstMatch
      XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
      XCTAssertTrue(field.isHittable)
      XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY)
      capture("log-again-keyboard-\(variant)")
    }
  }

  func testEmptyAmountDisablesLog() {
    launch("logAgain")
    let field = app.textFields[fieldName]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    replaceText(in: field, with: "")
    XCTAssertFalse(app.buttons["logAgainButton"].isEnabled)
    replaceText(in: field, with: "0")
    XCTAssertFalse(app.buttons["logAgainButton"].isEnabled)
    capture("log-again-invalid")
  }

  func testChangeAmountAndDayThenLog() {
    launch("logAgain")
    let field = app.textFields[fieldName]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    replaceText(in: field, with: "125")
    // 125 g of 250 g at 520 kcal.
    let total = app.staticTexts["logAgainTotal"]
    XCTAssertTrue(total.label.contains("260 kcal"), total.label)

    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    capture("log-again-before-day")
    app.buttons["logAgainDay"].tap()
    if !Calendar.current.isDate(yesterday, equalTo: .now, toGranularity: .month) {
      app.buttons["Previous Month"].tap()
    }
    // Calendar day buttons are labeled like "Thursday, November 5" (order depends on the locale).
    let weekday = yesterday.formatted(.dateTime.weekday(.wide))
    let month = yesterday.formatted(.dateTime.month(.wide))
    let day = app.buttons.matching(
      NSPredicate(format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@", weekday, month)
    ).firstMatch
    XCTAssertTrue(day.waitForExistence(timeout: 5), "\(weekday) \(month)")
    XCTAssertTrue(day.isHittable, day.label)
    day.tap()
    // Picking a day closes the calendar.
    XCTAssertTrue(day.waitForNonExistence(timeout: 5))

    let shortLabel = yesterday.formatted(.dateTime.month(.abbreviated).day())
    let log = app.buttons["logAgainButton"]
    XCTAssertTrue(
      log.wait(for: \.label, toEqual: "Log to \(shortLabel)", timeout: 5), log.label)
    capture("log-again-yesterday")
    log.tap()
    XCTAssertTrue(
      app.staticTexts["Meal logged to \(shortLabel)."].waitForExistence(timeout: 10))
    XCTAssertFalse(log.exists)
  }

  private func replaceText(in field: XCUIElement, with text: String) {
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    let current = field.value as? String ?? ""
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
    if !text.isEmpty { field.typeText(text) }
  }
}
