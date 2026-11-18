import EZHAKit
import Foundation
import Observation

/// Recent Cook suggestion titles, kept on this device for 7 days.
@MainActor
@Observable
final class SuggestionHistoryStore {
  private(set) var history: SuggestionHistory

  @ObservationIgnored private let defaults: UserDefaults?
  private static let key = "suggestionHistory"

  /// `defaults` nil keeps the history in memory only, for previews and the UI harness.
  init(defaults: UserDefaults? = .standard) {
    self.defaults = defaults
    if let data = defaults?.data(forKey: Self.key),
      let stored = try? JSONDecoder().decode(SuggestionHistory.self, from: data)
    {
      history = stored
    } else {
      history = SuggestionHistory()
    }
  }

  func recentTitles(now: Date = .now) -> [String] { history.titles(now: now) }

  func record(_ suggestions: [MealSuggestion], at date: Date = .now) {
    history.record(suggestions.map(\.title), at: date)
    if let data = try? JSONEncoder().encode(history) {
      defaults?.set(data, forKey: Self.key)
    }
  }
}
