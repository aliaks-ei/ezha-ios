import XCTest

/// Today spacing and the Logged meals list (PET-113): 0, 2 and 9 meals in every appearance.
@MainActor
final class TodayUITests: HarnessTestCase {
  private let variants = ["light", "dark", "large-text"]

  func testMealsAppearances() {
    for variant in variants {
      launch("today", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.staticTexts["Protein"].waitForExistence(timeout: 10))
      capture("today-meals-\(variant)")
      XCTAssertTrue(scroll(to: row("Greek yogurt, granola")))
      XCTAssertTrue(app.staticTexts.matching(label("Logged meals")).firstMatch.exists)
      capture("today-meals-end-\(variant)")
    }
  }

  func testEmptyAppearances() {
    for variant in variants {
      launch("todayEmpty", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.staticTexts["Protein"].waitForExistence(timeout: 10))
      XCTAssertTrue(scroll(to: app.buttons["Log meal"]))
      XCTAssertTrue(app.staticTexts["Nothing logged yet"].exists)
      capture("today-empty-\(variant)")
    }
  }

  func testManyMealsWithPendingAppearances() {
    for variant in variants {
      launch("todayMany", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.staticTexts["Protein"].waitForExistence(timeout: 10))
      capture("today-many-\(variant)")
      XCTAssertTrue(scroll(to: app.staticTexts["Includes 1 meal waiting to sync"]))
      capture("today-many-end-\(variant)")
    }
  }

  func testRowActionsStillWork() {
    launch("today")
    let meal = row("Chicken rice bowl")
    XCTAssertTrue(meal.waitForExistence(timeout: 10))
    meal.swipeLeft()
    XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
    capture("today-swipe")
    meal.swipeRight()  // Closes the swipe actions.
    XCTAssertFalse(app.buttons["Log again"].exists)
    meal.press(forDuration: 1.2)
    XCTAssertTrue(app.buttons["Log again"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Save as meal"].exists)
  }

  /// Swipes up until the element is on screen. Rows below the fold are not loaded yet.
  private func scroll(to element: XCUIElement) -> Bool {
    for _ in 0..<20 {
      if element.exists, element.isHittable { return true }
      app.collectionViews.firstMatch.swipeUp(velocity: .slow)
    }
    return element.exists && element.isHittable
  }

  private func label(_ text: String) -> NSPredicate {
    NSPredicate(format: "label ==[c] %@", text)
  }

  private func row(_ title: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
  }
}
