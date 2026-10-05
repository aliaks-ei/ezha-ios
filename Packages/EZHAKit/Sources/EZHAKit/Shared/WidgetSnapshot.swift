import Foundation

/// What the widget shows. Written by the app after each load of today.
public struct WidgetSnapshot: Codable, Sendable, Hashable {
  public var date: DateKey
  public var targetName: String?
  public var goals: MacroTotals
  public var totals: MacroTotals
  public var updatedAt: Date

  public init(
    date: DateKey, targetName: String?, goals: MacroTotals, totals: MacroTotals, updatedAt: Date
  ) {
    self.date = date
    self.targetName = targetName
    self.goals = goals
    self.totals = totals
    self.updatedAt = updatedAt
  }

  /// The snapshot as of `today`: an older snapshot becomes the new day with zero totals.
  public func asOf(_ today: DateKey) -> WidgetSnapshot {
    guard date < today else { return self }
    return WidgetSnapshot(
      date: today, targetName: targetName, goals: goals, totals: .zero, updatedAt: updatedAt)
  }

  public var remaining: MacroTotals { Macros.remaining(goals: goals, totals: totals) }

  public static let sample = WidgetSnapshot(
    date: .today(), targetName: "Basic", goals: .example,
    totals: MacroTotals(calories: 640, protein: 40, carbs: 70, fat: 20), updatedAt: .now)
}

/// Reads and writes the snapshot as JSON in the App Group container.
public enum SnapshotStore {
  public static let appGroup = "group.com.aliaksei.ezha"

  static var url: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appending(path: "widget-snapshot.json")
  }

  public static func read() -> WidgetSnapshot? {
    guard let url, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder.ezha.decode(WidgetSnapshot.self, from: data)
  }

  public static func write(_ snapshot: WidgetSnapshot) {
    guard let url, let data = try? JSONEncoder.ezha.encode(snapshot) else { return }
    try? data.write(to: url, options: .atomic)
  }

  public static func clear() {
    guard let url else { return }
    try? FileManager.default.removeItem(at: url)
  }
}
