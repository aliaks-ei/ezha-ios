import EZHAKit

/// All feature clients, injected once at the root.
struct AppClients: Sendable {
  var day: DayClient
  var logging: LoggingClient
  var library: LibraryClient
  var targets: TargetsClient
  var ai: AIClient
  var account: AccountClient

  static let live = AppClients(
    day: .live, logging: .live, library: .live, targets: .live, ai: .live, account: .live)
  static let preview = AppClients(
    day: .preview, logging: .preview, library: .preview, targets: .preview, ai: .preview,
    account: .preview)
}
