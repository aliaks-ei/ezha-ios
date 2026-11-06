import XCTest

/// PET-115: fiber eaten is display only. Today shows a line without a bar; unknown is never 0 g.
@MainActor
final class FiberUITests: HarnessTestCase {
  private let variants = ["light", "dark", "large-text"]

  private func element(_ id: String) -> XCUIElement {
    app.descendants(matching: .any)[id].firstMatch
  }

  /// Drags the content up until the element is fully on screen, in the top 60 % of the window
  /// (clear of bottom bars). Stops when the content no longer moves.
  private func reveal(_ element: XCUIElement) -> Bool {
    let window = app.windows.firstMatch
    var lastY: CGFloat?
    for _ in 0..<15 {
      if element.exists {
        if element.isHittable, element.frame.maxY < window.frame.height * 0.6 { return true }
        if element.frame.maxY == lastY { break }
        lastY = element.frame.maxY
      }
      window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        .press(
          forDuration: 0.05,
          thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
    }
    return element.exists && element.isHittable
  }

  func testTodayShowsFiberEaten() {
    for variant in variants {
      launch("todayFiber", dark: variant == "dark", large: variant == "large-text")
      let line = element("fiberLine")
      XCTAssertTrue(line.waitForExistence(timeout: 10))
      XCTAssertEqual(line.value as? String, "18 grams eaten")
      XCTAssertTrue(reveal(line))
      capture("fiber-today-\(variant)")
    }
  }

  func testTodayPartialFiberIsALowerBound() {
    for variant in variants {
      launch("todayFiberPartial", dark: variant == "dark", large: variant == "large-text")
      let line = element("fiberLine")
      XCTAssertTrue(line.waitForExistence(timeout: 10))
      XCTAssertEqual(line.value as? String, "At least 14 grams eaten. 1 meal has no fiber data")
      XCTAssertTrue(reveal(line))
      capture("fiber-today-partial-\(variant)")
    }
  }

  func testTodayWithoutFiberDataIsNotZero() {
    launch("today")
    let line = element("fiberLine")
    XCTAssertTrue(line.waitForExistence(timeout: 10))
    XCTAssertEqual(line.value as? String, "Not known. These meals have no fiber data")
    XCTAssertTrue(reveal(line))
    capture("fiber-today-unknown-light")
  }

  func testEntryDetailShowsFiber() {
    for variant in variants {
      launch("entryDetailFiber", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
      // The sauce has no fiber data, so the meal total is a lower bound.
      let total = app.staticTexts.matching(
        NSPredicate(format: "label ENDSWITH %@", "fiber at least 1 grams")
      ).firstMatch
      XCTAssertTrue(total.waitForExistence(timeout: 5))
      XCTAssertTrue(
        app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "fiber 0 grams"))
          .firstMatch.exists)
      capture("fiber-entry-detail-\(variant)")
    }
  }

  func testReviewShowsOptionalFiberRow() {
    for variant in variants {
      launch("reviewFiber", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 10))
      app.buttons["foodRow1"].tap()
      let rice = app.textFields["per100g-fiber1"]
      XCTAssertTrue(rice.waitForExistence(timeout: 5))
      XCTAssertEqual(rice.value as? String, "0.4")
      XCTAssertTrue(reveal(rice))
      capture("fiber-review-\(variant)")
    }
    // The estimate has no fiber for the chicken: the field is empty, not 0.
    launch("reviewFiber")
    XCTAssertTrue(app.buttons["loggerPrimary"].waitForExistence(timeout: 10))
    app.buttons["foodRow0"].tap()
    let chicken = app.textFields["per100g-fiber0"]
    XCTAssertTrue(chicken.waitForExistence(timeout: 5))
    XCTAssertNotEqual(chicken.value as? String, "0")
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Not known")).firstMatch
        .exists)
    capture("fiber-review-unknown-light")
  }

  func testFoodEditorHasOptionalFiber() {
    for variant in variants {
      launch("foodEditor", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 10))
      // Form rows below the fold are created only when scrolled into view.
      let fiber = app.textFields["fiberField"]
      XCTAssertTrue(reveal(fiber))
      XCTAssertEqual(fiber.placeholderValue, "Optional")
      capture("fiber-food-editor-\(variant)")
      if variant == "light" {
        fiber.tap()
        fiber.typeText("2.5")
        XCTAssertEqual(fiber.value as? String, "2.5")
        // Not under the keyboard once the form has scrolled.
        wait(
          for: [expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: fiber)],
          timeout: 5)
        capture("fiber-food-editor-typed-light")
      }
    }
  }
}
