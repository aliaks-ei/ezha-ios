import Foundation

/// Titles of recent Cook suggestions. The app sends them with the next request so the model
/// doesn't suggest the same meals again.
public struct SuggestionHistory: Codable, Sendable, Hashable {
  public struct Entry: Codable, Sendable, Hashable {
    public var title: String
    public var shownAt: Date

    public init(title: String, shownAt: Date) {
      self.title = title
      self.shownAt = shownAt
    }
  }

  /// How long a suggestion counts as recent.
  public static let window: TimeInterval = 7 * 24 * 60 * 60
  /// Most titles kept and sent.
  public static let limit = 30

  /// Newest first.
  public private(set) var entries: [Entry]

  public init(entries: [Entry] = []) {
    self.entries = entries
  }

  /// Unique titles shown within the window, newest first.
  public func titles(now: Date) -> [String] {
    entries.filter { now.timeIntervalSince($0.shownAt) < Self.window }.map(\.title)
  }

  /// Adds the titles just shown. A title shown again moves to the front.
  public mutating func record(_ titles: [String], at date: Date) {
    let fresh = titles.compactMap(\.trimmed.nonEmpty).reversed()
    for title in fresh {
      entries.removeAll { $0.title.caseInsensitiveCompare(title) == .orderedSame }
      entries.insert(Entry(title: title, shownAt: date), at: 0)
    }
    entries = Array(
      entries.filter { date.timeIntervalSince($0.shownAt) < Self.window }.prefix(Self.limit))
  }
}
