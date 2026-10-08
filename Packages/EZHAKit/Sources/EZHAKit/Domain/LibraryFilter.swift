import Foundation

/// Local time of day. Library "Usual now" counts logs per slot.
public enum TimeSlot: String, Codable, Sendable, CaseIterable {
  case morning
  case midday
  case evening

  /// Morning 05:00–10:59, midday 11:00–16:59, evening 17:00–04:59.
  public init(date: Date, calendar: Calendar = .current) {
    switch calendar.component(.hour, from: date) {
    case 5..<11: self = .morning
    case 11..<17: self = .midday
    default: self = .evening
    }
  }
}

/// One Library list section: pinned groups first, then every item under its first letter.
public struct LibrarySection: Identifiable, Sendable, Hashable {
  public enum Kind: Sendable, Hashable {
    case usual(TimeSlot)
    case favorites
    case recent
    case letter(String)
  }

  public var kind: Kind
  public var foods: [SavedFood]

  public var id: String {
    switch kind {
    case .usual: "usual"
    case .favorites: "favorites"
    case .recent: "recent"
    case .letter(let letter): "letter-\(letter)"
    }
  }
}

/// Library list rules. Port of `src/features/library/library-helpers.ts`.
public enum LibraryFilter: String, CaseIterable, Codable, Sendable, Identifiable {
  case all
  case foods
  case meals

  public var id: String { rawValue }

  public static let maxRecent = 16
  /// Logs in one time slot before an item counts as usual then.
  public static let usualMinUses = 3
  public static let maxUsual = 5
  public static let maxRecentSection = 6
  public static let recentDays = 7

  /// Keeps foods or meals. With a search, keeps items where every term matches and ranks them:
  /// name starts with the term, then a word starts with it, then it contains it, then one typo.
  /// Ties go to the most used, then the most recent, then by name.
  public func apply(to foods: [SavedFood], search: String) -> [SavedFood] {
    let kept = foods.filter { food in
      switch self {
      case .all: true
      case .foods: !food.isMeal
      case .meals: food.isMeal
      }
    }
    let terms = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    guard !terms.isEmpty else { return kept }
    return kept.compactMap { food -> (SavedFood, Int)? in
      let name = food.name.lowercased()
      var total = 0
      for term in terms {
        let score = Self.score(term, in: name)
        guard score > 0 else { return nil }
        total += score
      }
      return (food, total)
    }
    .sorted { a, b in
      if a.1 != b.1 { return a.1 > b.1 }
      if a.0.useCount != b.0.useCount { return a.0.useCount > b.0.useCount }
      let aUsed = a.0.lastUsedAt ?? .distantPast
      let bUsed = b.0.lastUsedAt ?? .distantPast
      if aUsed != bUsed { return aUsed > bUsed }
      return a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending
    }
    .map(\.0)
  }

  /// 4 name prefix, 3 word prefix, 2 substring, 1 one typo (terms of 5+ letters), 0 no match.
  static func score(_ term: String, in name: String) -> Int {
    if name.hasPrefix(term) { return 4 }
    let words = name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    if words.contains(where: { $0.hasPrefix(term) }) { return 3 }
    if name.contains(term) { return 2 }
    guard term.count >= 5 else { return 0 }
    let typo = words.contains { word in
      (-1...1).contains { delta in
        editDistance(term, String(word.prefix(term.count + delta))) <= 1
      }
    }
    return typo ? 1 : 0
  }

  static func editDistance(_ a: String, _ b: String) -> Int {
    let b = Array(b)
    var row = Array(0...b.count)
    for (i, x) in a.enumerated() {
      var diagonal = row[0]
      row[0] = i + 1
      for (j, y) in b.enumerated() {
        let above = row[j + 1]
        row[j + 1] = min(above + 1, row[j] + 1, diagonal + (x == y ? 0 : 1))
        diagonal = above
      }
    }
    return row[b.count]
  }

  /// "Usual now", Favorites, and Recent, each item once, then every item A–Z by first letter.
  public static func sections(
    _ foods: [SavedFood], now: Date = .now, calendar: Calendar = .current
  ) -> [LibrarySection] {
    let slot = TimeSlot(date: now, calendar: calendar)
    var shown = Set<UUID>()
    func take(_ list: [SavedFood], limit: Int = .max) -> [SavedFood] {
      let picked = list.filter { !shown.contains($0.id) }.prefix(limit)
      shown.formUnion(picked.map(\.id))
      return Array(picked)
    }
    let usual = take(
      foods.filter { $0.uses(in: slot) >= usualMinUses }
        .sorted {
          $0.uses(in: slot) != $1.uses(in: slot)
            ? $0.uses(in: slot) > $1.uses(in: slot)
            : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }, limit: maxUsual)
    let favorites = take(
      foods.filter(\.isFavorite).sorted {
        $0.useCount != $1.useCount
          ? $0.useCount > $1.useCount
          : $0.name.localizedStandardCompare($1.name) == .orderedAscending
      })
    let cutoff = calendar.date(byAdding: .day, value: -recentDays, to: now) ?? now
    let recent = take(
      foods.filter { ($0.lastUsedAt ?? .distantPast) >= cutoff }
        .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) },
      limit: maxRecentSection)

    var pinned: [LibrarySection] = []
    if !usual.isEmpty { pinned.append(LibrarySection(kind: .usual(slot), foods: usual)) }
    if !favorites.isEmpty { pinned.append(LibrarySection(kind: .favorites, foods: favorites)) }
    if !recent.isEmpty { pinned.append(LibrarySection(kind: .recent, foods: recent)) }

    let byLetter = Dictionary(grouping: foods, by: letter)
    let letters = byLetter.keys.sorted { a, b in
      if a == "#" || b == "#" { return b == "#" && a != "#" }
      return a.localizedStandardCompare(b) == .orderedAscending
    }
    return pinned
      + letters.map { key in
        LibrarySection(
          kind: .letter(key),
          foods: (byLetter[key] ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
          })
      }
  }

  /// First letter without accents, uppercased. "#" for digits and symbols.
  static func letter(_ food: SavedFood) -> String {
    guard let first = food.name.trimmed.first, first.isLetter else { return "#" }
    return String(first).folding(options: [.diacriticInsensitive], locale: nil).uppercased()
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
