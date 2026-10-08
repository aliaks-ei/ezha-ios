import XCTest

/// Launches the harness app on one scenario and saves screenshots as test attachments.
@MainActor
class HarnessTestCase: XCTestCase {
  var app = XCUIApplication()

  override func setUp() {
    continueAfterFailure = false
  }

  func launch(_ scenario: String, dark: Bool = false, large: Bool = false) {
    app.terminate()
    app.launchEnvironment["HARNESS_SCENARIO"] = scenario
    app.launchEnvironment["HARNESS_APPEARANCE"] = dark ? "dark" : "light"
    app.launchEnvironment["HARNESS_LARGE_TEXT"] = large ? "1" : "0"
    app.launch()
  }

  /// Saved as "<screen width>-<name>" so runs on different devices do not collide.
  func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "\(Int(app.windows.firstMatch.frame.width))-\(name)"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
