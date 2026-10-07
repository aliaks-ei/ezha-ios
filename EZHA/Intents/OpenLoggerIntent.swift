import AppIntents
import Foundation

/// Opens the app on the logger for today. Compiled into the app and the widget extension
/// (the Control Center control runs it). The system runs `perform` in the app.
struct OpenLoggerIntent: AppIntent {
  static let title: LocalizedStringResource = "Log a meal"
  static let description = IntentDescription("Opens Ezha on the logger for today.")
  static let supportedModes: IntentModes = .foreground

  /// Set by the app at launch. Nil in the widget extension.
  @MainActor static var handler: (() -> Void)?

  static let appGroup = "group.com.aliaksei.ezha"
  static let pendingKey = "openLoggerRequested"

  @MainActor
  func perform() async throws -> some IntentResult {
    if let handler = Self.handler {
      handler()
    } else {
      UserDefaults(suiteName: Self.appGroup)?.set(true, forKey: Self.pendingKey)
    }
    return .result()
  }

  /// Returns and clears a request left by another process.
  static func consumePendingRequest() -> Bool {
    let defaults = UserDefaults(suiteName: appGroup)
    guard defaults?.bool(forKey: pendingKey) == true else { return false }
    defaults?.removeObject(forKey: pendingKey)
    return true
  }
}
