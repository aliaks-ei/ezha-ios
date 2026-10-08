import XCTest

/// Fresh audit evidence from production views with fixture clients, without account mutations.
@MainActor
final class AuditUITests: HarnessTestCase {
  private func appearances(_ scenario: String, ready: String) {
    for variant in ["light", "dark", "large-text"] {
      launch(scenario, dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.staticTexts[ready].firstMatch.waitForExistence(timeout: 10))
      capture("audit-\(scenario)-\(variant)")
    }
  }

  func testTodayAppearances() {
    appearances("today", ready: "Protein")
  }

  func testSettingsAppearances() {
    appearances("settings", ready: "Daily targets")
  }

  func testSuggestionsAppearances() {
    appearances("suggestions", ready: "Remaining")
    app.swipeUp()
    capture("audit-suggestions-large-text-scrolled")
  }

  func testAuthAppearances() {
    appearances("auth", ready: "Ezha")
    XCTAssertTrue(app.buttons["Continue with email"].isHittable)
  }

  func testOnboardingAppearances() {
    appearances("onboarding", ready: "Calories and macros per day")
    XCTAssertTrue(app.buttons["Continue"].isHittable)
  }

  func testConsentAppearances() {
    appearances("consent", ready: "Your saved library and manual logging work without AI.")
    XCTAssertTrue(app.buttons["Allow"].isHittable)
    XCTAssertTrue(app.buttons["Not now"].isHittable)
  }

  func testShellNavigationAndLogger() {
    launch("shell")
    XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 10))
    capture("audit-shell-light")
    app.tabBars.buttons["Library"].tap()
    XCTAssertTrue(app.staticTexts["Greek yogurt"].firstMatch.waitForExistence(timeout: 10))
    capture("audit-shell-library")
    app.tabBars.buttons["Settings"].tap()
    XCTAssertTrue(app.staticTexts["Daily targets"].waitForExistence(timeout: 5))
    app.tabBars.buttons["Log meal"].tap()
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 10))
    XCTAssertEqual(app.buttons["loggerPrimary"].label, "Estimate nutrition")
    capture("audit-shell-logger")
    launch("shell", dark: true)
    XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 10))
    capture("audit-shell-dark")
    launch("shell", large: true)
    XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 10))
    capture("audit-shell-large-text")
  }

  func testLoggerEntryAppearancesAndCloseDiscards() {
    appearances("entry", ready: "What did you eat?")
    let field =
      app.textFields["mealText"].exists
      ? app.textFields["mealText"] : app.textViews["mealText"]
    app.swipeUp()
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
    field.typeText("Chicken 100 g")
    capture("audit-entry-large-text-keyboard")
    app.buttons["Close"].firstMatch.tap()
    app.alerts.buttons["Discard draft"].tap()
    XCTAssertTrue(app.buttons["Open logger"].waitForExistence(timeout: 5))
    app.buttons["Open logger"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertFalse((field.value as? String ?? "").contains("Chicken 100 g"))
  }

  func testReviewedMealLogsAndDismisses() {
    launch("review")
    let log = app.buttons["loggerPrimary"]
    XCTAssertTrue(log.waitForExistence(timeout: 10))
    XCTAssertEqual(log.label, "Log meal")
    log.tap()
    XCTAssertTrue(log.waitForNonExistence(timeout: 10))
    XCTAssertTrue(app.buttons["Open logger"].isHittable)
    capture("audit-reviewed-meal-logged")
  }

  func testSavedFoodLogsAndDismisses() {
    launch("libraryTab")
    let yogurt = app.staticTexts["Greek yogurt"].firstMatch
    XCTAssertTrue(yogurt.waitForExistence(timeout: 10))
    yogurt.tap()
    let log = app.buttons["Log to Today"]
    XCTAssertTrue(log.waitForExistence(timeout: 5))
    capture("audit-quicklog-before")
    log.tap()
    XCTAssertTrue(log.waitForNonExistence(timeout: 10))
    XCTAssertTrue(yogurt.isHittable)
    capture("audit-quicklog-logged")
  }
}
