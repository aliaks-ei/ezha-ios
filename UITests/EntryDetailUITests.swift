import XCTest

/// Logged-meal detail sheet (PET-106): the Delete row icon and text are both red.
@MainActor
final class EntryDetailUITests: HarnessTestCase {
  func testDeleteRowLight() { checkActions("light") }
  func testDeleteRowDark() { checkActions("dark", dark: true) }

  private func checkActions(_ name: String, dark: Bool = false) {
    launch("entryDetail", dark: dark)
    XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
    // Expand the sheet to the large detent so the actions section is on screen.
    let grabber = app.buttons["Sheet Grabber"]
    if grabber.exists, grabber.value as? String != "Full screen" { grabber.tap() }
    let delete = app.buttons["entryDelete"]
    if !delete.waitForExistence(timeout: 5) { app.collectionViews.firstMatch.swipeUp() }
    XCTAssertTrue(delete.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Log again"].exists)
    XCTAssertTrue(app.buttons["Save as meal"].exists)
    capture("entry-detail-\(name)")
  }
}
