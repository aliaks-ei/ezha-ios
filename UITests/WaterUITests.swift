import XCTest

/// Water tracking (PET-116): the Today card under, at, and over target and with no target,
/// quick add with undo, offline logging, custom amounts in other units, editing and deleting
/// entries, and the water target in the target editor.
@MainActor
final class WaterUITests: HarnessTestCase {
  private let variants = ["light", "dark", "large-text"]

  func testTodayWaterStates() {
    let states = [
      ("todayWater", "750 ml left", "under"),
      ("todayWaterAt", "Target reached", "at"),
      ("todayWaterOver", "400 ml over", "over"),
      ("todayWaterNone", "ml today", "none"),
    ]
    for (scenario, expected, name) in states {
      for variant in variants {
        launch(scenario, dark: variant == "dark", large: variant == "large-text")
        let summary = app.descendants(matching: .any)["waterSummary"]
        // At large text sizes the card is below the fold, and List loads it only after a scroll.
        XCTAssertTrue(app.staticTexts["Protein"].waitForExistence(timeout: 10))
        XCTAssertTrue(scroll(to: summary), "\(scenario) \(variant)")
        XCTAssertTrue(app.buttons["waterOther"].exists, "\(scenario) \(variant)")
        XCTAssertTrue(
          summary.label.localizedCaseInsensitiveContains(expected),
          "\(scenario) \(variant): \(summary.label)")
        if scenario == "todayWaterNone" {
          XCTAssertTrue(app.buttons["waterSetTarget"].exists)
        }
        capture("water-today-\(name)-\(variant)")
      }
    }
  }

  func testQuickAddShowsUndoAndUndoRemovesIt() {
    launch("todayWater")
    let add = app.buttons["waterQuickAdd0"]
    XCTAssertTrue(add.waitForExistence(timeout: 10))
    XCTAssertEqual(add.label, "Add Glass, 250 ml")
    add.tap()
    XCTAssertTrue(app.staticTexts["Added 250 ml of water"].waitForExistence(timeout: 5))
    XCTAssertTrue(waitForSummary(amount: "1500"))
    XCTAssertTrue(app.buttons["waterEntriesButton"].label.contains("5"))
    capture("water-quick-add")
    app.buttons["Undo"].tap()
    XCTAssertTrue(waitForSummary(amount: "1250"))
    XCTAssertTrue(app.buttons["waterEntriesButton"].label.contains("4"))
  }

  func testOfflineQuickAddWaitsToSync() {
    launch("todayWaterOffline")
    let add = app.buttons["waterQuickAdd1"]
    XCTAssertTrue(add.waitForExistence(timeout: 10))
    add.tap()
    XCTAssertTrue(waitForSummary(amount: "1750"))
    app.buttons["waterEntriesButton"].tap()
    XCTAssertTrue(app.staticTexts["Waiting to sync"].waitForExistence(timeout: 5))
    capture("water-offline-pending")
  }

  func testCustomAmountInCups() {
    launch("todayWater")
    let other = app.buttons["waterOther"]
    XCTAssertTrue(other.waitForExistence(timeout: 10))
    other.tap()
    let field = app.textFields["waterAmountField"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.typeText("2")
    app.buttons["waterUnitPicker"].tap()
    app.buttons["Cup"].tap()
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "= 480 ml")).firstMatch
        .waitForExistence(timeout: 5))
    capture("water-add-cups")
    app.buttons["waterSave"].tap()
    XCTAssertTrue(waitForSummary(amount: "1730"))
  }

  func testInvalidAmountDisablesAdd() {
    launch("waterAdd")
    let field = app.textFields["waterAmountField"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    field.typeText("0")
    XCTAssertTrue(app.staticTexts["waterAmountError"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["waterSave"].isEnabled)
    capture("water-add-invalid")
  }

  func testAddSheetAppearances() {
    for variant in variants {
      launch("waterAdd", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.textFields["waterAmountField"].waitForExistence(timeout: 10))
      app.textFields["waterAmountField"].typeText("1.5")
      app.buttons["waterUnitPicker"].tap()
      app.buttons["l"].tap()
      XCTAssertTrue(app.descendants(matching: .any)["waterConversion"].waitForExistence(timeout: 5))
      capture("water-add-\(variant)")
    }
  }

  func testEntriesAppearances() {
    for variant in variants {
      launch("waterEntries", dark: variant == "dark", large: variant == "large-text")
      XCTAssertTrue(app.buttons["waterRow"].firstMatch.waitForExistence(timeout: 10))
      XCTAssertEqual(app.buttons.matching(identifier: "waterRow").count, 4)
      XCTAssertTrue(app.staticTexts["Waiting to sync"].exists)
      capture("water-entries-\(variant)")
    }
  }

  func testEditAndDeleteEntries() {
    launch("waterEntries")
    let first = app.buttons["waterRow"].firstMatch
    XCTAssertTrue(first.waitForExistence(timeout: 10))
    first.tap()
    let field = app.textFields["waterAmountField"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.value as? String, "170")
    field.tap()
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "400")
    capture("water-edit")
    app.buttons["waterSave"].tap()
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "400 ml")).firstMatch
        .waitForExistence(timeout: 5))
    XCTAssertTrue(waitForSummary(amount: "1480"))

    let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "500 ml")).firstMatch
    row.swipeLeft()
    app.buttons["Delete"].tap()
    XCTAssertTrue(app.staticTexts["Water entry deleted"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons.matching(identifier: "waterRow").count, 3)
    capture("water-deleted")
    app.buttons["Undo"].tap()
    XCTAssertTrue(waitForRows(4))
  }

  func testTargetEditorWater() {
    for variant in variants {
      launch("waterTargetEditor", dark: variant == "dark", large: variant == "large-text")
      let toggle = app.switches["waterTargetToggle"]
      XCTAssertTrue(scrollForm(to: toggle))
      XCTAssertEqual(app.textFields["waterTargetField"].value as? String, "2000")
      capture("water-target-\(variant)")
    }
    launch("waterTargetEditor")
    XCTAssertTrue(scrollForm(to: app.switches["waterTargetToggle"]))
    app.segmentedControls["waterTargetUnit"].buttons["l"].tap()
    XCTAssertEqual(app.textFields["waterTargetField"].value as? String, "2")
    XCTAssertTrue(app.buttons["targetSave"].isEnabled)
    let toggle = app.switches["waterTargetToggle"]
    toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    XCTAssertFalse(app.textFields["waterTargetField"].exists)
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No water target"))
        .firstMatch.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["targetSave"].isEnabled)
    capture("water-target-off")
  }

  // MARK: Helpers

  /// Waits until the summary starts with the amount, "1500" matching "1,500" or "1 500" in any
  /// locale's grouping.
  private func waitForSummary(amount: String) -> Bool {
    let summary = app.descendants(matching: .any)["waterSummary"]
    let pattern = "^" + amount.dropLast(3) + ".?" + amount.suffix(3) + "\\D.*"
    let predicate = NSPredicate(format: "label MATCHES %@", pattern)
    return XCTWaiter.wait(
      for: [XCTNSPredicateExpectation(predicate: predicate, object: summary)], timeout: 5)
      == .completed
  }

  private func waitForRows(_ count: Int) -> Bool {
    let predicate = NSPredicate(format: "count == %d", count)
    return XCTWaiter.wait(
      for: [
        XCTNSPredicateExpectation(
          predicate: predicate, object: app.buttons.matching(identifier: "waterRow"))
      ], timeout: 5) == .completed
  }

  /// Swipes up until the element is on screen. Rows below the fold are not loaded yet.
  private func scroll(to element: XCUIElement) -> Bool {
    for _ in 0..<20 {
      if element.exists, element.isHittable { return true }
      app.collectionViews.firstMatch.swipeUp(velocity: .slow)
    }
    return element.exists && element.isHittable
  }

  private func scrollForm(to element: XCUIElement) -> Bool {
    _ = element.waitForExistence(timeout: 10)
    return scroll(to: element)
  }
}
