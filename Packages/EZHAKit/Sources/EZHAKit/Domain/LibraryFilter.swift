import Foundation

/// Library list rules. Port of `src/features/library/library-helpers.ts`.
public enum LibraryFilter: String, CaseIterable, Codable, Sendable, Identifiable {
  case all
  case foods
  case meals
  case favorites

  public var id: String { rawValue }

  public static let maxRecent = 16

  /// Every whitespace-separated term must be in the name, case-insensitive, any order.
  public func apply(to foods: [SavedFood], search: String) -> [SavedFood] {
    let terms = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    return foods.filter { food in
      switch self {
      case .foods where food.isMeal, .meals where !food.isMeal,
        .favorites where !food.isFavorite:
        return false
      default:
        let name = food.name.lowercased()
        return terms.allSatisfy { name.contains($0) }
      }
    }
  }

  /// Recently used first (`last_used_at` desc, up to 16), then by name.
  public static func sorted(_ foods: [SavedFood]) -> [SavedFood] {
    let recent = foods.filter { $0.lastUsedAt != nil }
      .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
      .prefix(maxRecent)
    let recentIds = Set(recent.map(\.id))
    let rest = foods.filter { !recentIds.contains($0.id) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    return Array(recent) + rest
  }

  /// "Saved meal", "Per 100g · N kcal", or "<size> <unit> · N kcal".
  public static func subtitle(_ food: SavedFood) -> String {
    if food.isMeal { return "Saved meal" }
    if food.unitType == .perServing, let size = food.servingSize, size > 0 {
      let kcal = Macros.resolvedPerServing(food).calories.rounded()
      let unit = food.servingUnit?.trimmed.nonEmpty ?? LibraryDrafts.defaultServingUnit
      return
        "\(Macros.format(size, maxFractionDigits: 1)) \(unit) · \(Macros.format(kcal, maxFractionDigits: 0)) kcal"
    }
    let kcal = Macros.resolvedPer100g(food).calories.rounded()
    return "Per 100g · \(Macros.format(kcal, maxFractionDigits: 0)) kcal"
  }
}
