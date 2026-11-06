import Foundation

/// Port of `src/lib/macros.ts`.
public enum Macros {
  /// round(eaten / target × 100), minimum 0. 0 when the target is not set.
  public static func progressPercent(eaten: Double, target: Double) -> Int {
    guard target > 0 else { return 0 }
    return max(0, Int((eaten / target * 100).rounded()))
  }

  /// Bar width in percent, capped at 100.
  public static func barPercent(eaten: Double, target: Double) -> Int {
    min(progressPercent(eaten: eaten, target: target), 100)
  }

  /// Sum per macro, each rounded to an integer.
  public static func dayTotals(_ entries: [FoodEntry]) -> MacroTotals {
    entries.reduce(MacroTotals.zero) { $0 + $1.macros }.rounded
  }

  /// target − totals per macro, not clamped.
  public static func remaining(goals: MacroTotals, totals: MacroTotals) -> MacroTotals {
    MacroTotals(
      calories: goals.calories - totals.calories,
      protein: goals.protein - totals.protein,
      carbs: goals.carbs - totals.carbs,
      fat: goals.fat - totals.fat
    )
  }

  /// Calories for the ring: "N kcal left" or, when eaten > goal, "N kcal over".
  public static func calorieStatus(goal: Double, eaten: Double) -> (value: Double, isOver: Bool) {
    eaten > goal && goal > 0 ? (eaten - goal, true) : (max(0, goal - eaten), false)
  }

  /// Per-serving values, or per-100 g × serving size / 100 when they are all zero.
  public static func resolvedPerServing(_ food: SavedFood) -> MacroTotals {
    let perServing = food.perServing
    if perServing.calories > 0 || perServing.protein > 0 || perServing.carbs > 0
      || perServing.fat > 0
    {
      return perServing
    }
    guard let size = food.servingSize, size > 0 else { return .zero }
    return food.per100g.scaled(by: size / 100)
  }

  /// Per-100 g values, or per-serving values scaled by 100 / serving size when they are all zero.
  public static func resolvedPer100g(_ food: SavedFood) -> MacroTotals {
    let per100 = food.per100g
    if per100.calories > 0 || per100.protein > 0 || per100.carbs > 0 || per100.fat > 0 {
      return per100
    }
    guard let size = food.servingSize, size > 0 else { return .zero }
    return resolvedPerServing(food).scaled(by: 100 / size)
  }

  public static func forQuantity(_ food: SavedFood, grams: Double) -> MacroTotals {
    resolvedPer100g(food).scaled(by: grams / 100)
  }

  /// No grouping, up to `maxFractionDigits` fraction digits. "12.5", "100".
  public static func format(_ value: Double, maxFractionDigits: Int = 2) -> String {
    value.formatted(
      .number.grouping(.never).precision(.fractionLength(0...maxFractionDigits))
        .locale(Locale(identifier: "en_US_POSIX")))
  }

  /// "4/4/9" calories from macros, for the onboarding hint.
  public static func caloriesFromMacros(protein: Double, carbs: Double, fat: Double) -> Double {
    protein * 4 + carbs * 4 + fat * 9
  }
}

/// The fiber eaten in a day. Fiber has no goal; this is display data only.
public struct FiberSummary: Sendable, Hashable {
  /// Sum of the known values, in grams. Nil when meals are logged but none has fiber data.
  public var grams: Double?
  /// Meals with at least one food without fiber data. Their known foods still count in `grams`.
  public var unknownMeals: Int

  public init(grams: Double?, unknownMeals: Int) {
    self.grams = grams
    self.unknownMeals = unknownMeals
  }

  /// True when `grams` is the full total. False when it is a lower bound or unknown.
  public var isComplete: Bool { unknownMeals == 0 && grams != nil }

  /// A day with no meals: 0 g is known. Meals without any fiber data: unknown, not 0.
  public static func day(_ entries: [DayEntry]) -> FiberSummary {
    var grams: Double?
    var unknown = 0
    for entry in entries {
      if let fiber = entryFiber(entry) { grams = (grams ?? 0) + fiber }
      if !isEntryComplete(entry) { unknown += 1 }
    }
    return FiberSummary(grams: entries.isEmpty ? 0 : grams, unknownMeals: unknown)
  }

  /// The entry's known fiber: its stored sum, or the sum of its known items.
  public static func entryFiber(_ entry: DayEntry) -> Double? {
    if let fiber = entry.entry.fiber { return fiber }
    let known = entry.items.compactMap(\.fiber)
    return known.isEmpty ? nil : known.reduce(0, +)
  }

  /// Every item has fiber, or (an entry without items) the entry has it.
  public static func isEntryComplete(_ entry: DayEntry) -> Bool {
    entry.items.isEmpty ? entry.entry.fiber != nil : entry.items.allSatisfy { $0.fiber != nil }
  }
}
