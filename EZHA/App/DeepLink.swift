import Foundation

/// `ezha://` links: OAuth and recovery callbacks, plus widget and intent routes.
enum DeepLink: Equatable {
  case authCallback(URL)
  case today
  case log
  case suggestions
  case library
  case settings

  init?(_ url: URL) {
    guard url.scheme == "ezha" else { return nil }
    switch url.host() {
    case "login-callback", "reset-password": self = .authCallback(url)
    case "today": self = .today
    case "log": self = .log
    case "suggestions": self = .suggestions
    case "library": self = .library
    case "settings": self = .settings
    default: return nil
    }
  }
}
