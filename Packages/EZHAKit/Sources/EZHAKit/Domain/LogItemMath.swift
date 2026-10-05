import Foundation

/// One editable item in the logger. Port of `LogMealItem` in
/// `src/features/add-log/log-meal-service.ts`.
public struct LogItem: Codable, Sendable, Hashable, Identifiable {
  public enum MacroBasis: String, Codable, Sendable {
    case per100g
    case perOriginal
  }

  public enum Origin: String, Codable, Sendable {
    case ai
    case libraryFood
    case libraryMeal
  }

  public var id: UUID
  public var name: String
  public var gramsText: String
  public var macroBasis: MacroBasis
  public var baseGrams: Double
  public var base: MacroTotals
  public var origin: Origin
  public var linkedFoodId: UUID?
  public var aiConfidence: Double?
  public var aiNotes: String
  public var isNutritionMissing: Bool

  public init(
    id: UUID = UUID(), name: String, gramsText: String, macroBasis: MacroBasis,
    baseGrams: Double, base: MacroTotals, origin: Origin, linkedFoodId: UUID? = nil,
    aiConfidence: Double? = nil, aiNotes: String = "", isNutritionMissing: Bool = false
  ) {
    self.id = id
    self.name = name
    self.gramsText = gramsText
    self.macroBasis = macroBasis
    self.baseGrams = baseGrams
    self.base = base
    self.origin = origin
    self.linkedFoodId = linkedFoodId
    self.aiConfidence = aiConfidence
    self.aiNotes = aiNotes
    self.isNutritionMissing = isNutritionMissing
  }
}

public enum LogItemMath {
  public static let maxGrams: Double = 5000
  public static let stepGrams: Double = 5
  public static let maxGramsMessage = "Max grams per item is 5000g."

  /// Parsed grams clamped to 0...5000, or nil when the text is not a number.
  public static func normalizedGrams(_ text: String) -> Double? {
    guard let value = parseNumberInput(text) else { return nil }
    return min(max(value, 0), maxGrams)
  }

  /// Grams that are valid for logging (> 0), or nil.
  public static func validGrams(_ text: String) -> Double? {
    guard let grams = normalizedGrams(text), grams > 0 else { return nil }
    return grams
  }

  /// Item macros at its current grams.
  public static func macros(_ item: LogItem) -> MacroTotals {
    guard !item.isNutritionMissing, let grams = normalizedGrams(item.gramsText), grams > 0 else {
      return .zero
    }
    let factor =
      switch item.macroBasis {
      case .per100g: grams / 100
      case .perOriginal: grams / (item.baseGrams > 0 ? item.baseGrams : 1)
      }
    return item.base.scaled(by: factor)
  }

  public static func totals(_ items: [LogItem]) -> MacroTotals {
    items.reduce(.zero) { $0 + macros($1) }
  }

  /// ±5 g stepper, clamped to 0...5000. `hitMax` is true when the result is at the limit.
  public static func step(_ gramsText: String, by delta: Double) -> (text: String, hitMax: Bool) {
    let current = normalizedGrams(gramsText) ?? 0
    let next = min(max(current + delta, 0), maxGrams)
    return (Macros.format(next, maxFractionDigits: 1), delta > 0 && next >= maxGrams)
  }

  /// The grams text to restore when a field loses focus with invalid text.
  /// Item's last valid value, then (for library foods) the food's last valid value, then base grams.
  public static func restoredGramsText(
    for item: LogItem, lastValidByItem: [UUID: String], lastValidByFood: [UUID: String]
  ) -> String {
    if validGrams(item.gramsText) != nil { return item.gramsText }
    if let text = lastValidByItem[item.id] { return text }
    if item.origin == .libraryFood, let food = item.linkedFoodId, let text = lastValidByFood[food] {
      return text
    }
    return Macros.format(item.baseGrams > 0 ? item.baseGrams : 100, maxFractionDigits: 1)
  }

  // MARK: Builders

  public static func fromSavedFood(_ food: SavedFood, grams: Double? = nil) -> LogItem {
    let grams = grams.flatMap { $0 > 0 ? $0 : nil } ?? defaultGrams(food)
    return LogItem(
      name: food.name,
      gramsText: Macros.format(grams, maxFractionDigits: 1),
      macroBasis: .per100g,
      baseGrams: 100,
      base: Macros.resolvedPer100g(food),
      origin: .libraryFood,
      linkedFoodId: food.id,
      aiNotes: "Added from library food"
    )
  }

  /// Serving size for per-serving foods, else 100 g.
  public static func defaultGrams(_ food: SavedFood) -> Double {
    if food.unitType == .perServing, let size = food.servingSize, size > 0 { return size }
    return 100
  }

  /// Each ingredient converted to per-100 g. Grams ≤ 0 or non-finite macros mark it missing.
  public static func fromSavedMeal(_ ingredients: [SavedMealIngredient]) -> [LogItem] {
    ingredients.map { ingredient in
      let grams = ingredient.grams.isFinite && ingredient.grams > 0 ? ingredient.grams : 0
      let values = [ingredient.calories, ingredient.protein, ingredient.carbs, ingredient.fat]
      let missing = grams <= 0 || values.contains { !$0.isFinite }
      return LogItem(
        name: ingredient.name,
        gramsText: Macros.format(grams, maxFractionDigits: 1),
        macroBasis: .per100g,
        baseGrams: 100,
        base: missing ? .zero : ingredient.macros.scaled(by: 100 / grams),
        origin: .libraryMeal,
        linkedFoodId: ingredient.linkedFoodId,
        aiNotes: missing ? "Missing nutrition" : "Added from saved meal",
        isNutritionMissing: missing
      )
    }
  }

  /// One item per estimate item (per original grams). With no items, one item named by the estimate.
  public static func fromEstimate(_ estimate: Estimate, fallbackName: String = "AI item")
    -> [LogItem]
  {
    let items = estimate.items.filter { !$0.name.trimmed.isEmpty }
    guard !items.isEmpty else {
      return [
        LogItem(
          name: estimate.foodName?.trimmed.nonEmpty ?? fallbackName,
          gramsText: "100",
          macroBasis: .perOriginal,
          baseGrams: 100,
          base: estimate.totals,
          origin: .ai,
          aiConfidence: estimate.confidence,
          aiNotes: estimate.notes
        )
      ]
    }
    return items.map { item in
      let grams = item.grams.isFinite && item.grams > 0 ? item.grams : 1
      return LogItem(
        name: item.name.trimmed,
        gramsText: Macros.format(grams, maxFractionDigits: 1),
        macroBasis: .perOriginal,
        baseGrams: grams,
        base: item.macros,
        origin: .ai,
        aiConfidence: item.confidence ?? estimate.confidence,
        aiNotes: item.notes ?? estimate.notes
      )
    }
  }

  /// Label results are per 100 g. Grams = grams eaten, or 100.
  public static func fromLabelEstimate(
    _ estimate: Estimate, grams: Double?, fallbackName: String = "Nutrition label"
  ) -> [LogItem] {
    let grams = grams.flatMap { $0 > 0 ? $0 : nil } ?? 100
    let gramsText = Macros.format(grams, maxFractionDigits: 1)
    let items = estimate.items.filter { !$0.name.trimmed.isEmpty }
    guard !items.isEmpty else {
      return [
        LogItem(
          name: estimate.foodName?.trimmed.nonEmpty ?? fallbackName,
          gramsText: gramsText, macroBasis: .per100g, baseGrams: 100, base: estimate.totals,
          origin: .ai, aiConfidence: estimate.confidence, aiNotes: estimate.notes)
      ]
    }
    return items.map { item in
      LogItem(
        name: item.name.trimmed, gramsText: gramsText, macroBasis: .per100g, baseGrams: 100,
        base: item.macros, origin: .ai, aiConfidence: item.confidence ?? estimate.confidence,
        aiNotes: item.notes ?? estimate.notes)
    }
  }

  /// A new estimate replaces only the AI items. Library items stay.
  public static func replacingAIItems(in items: [LogItem], with newItems: [LogItem]) -> [LogItem] {
    items.filter { $0.origin != .ai } + newItems
  }

  /// Per-100 g values scaled to `grams`. Returns the input when grams is not set.
  public static func scalePer100g(_ base: MacroTotals, grams: Double?) -> MacroTotals {
    guard let grams, grams > 0 else { return base }
    return base.scaled(by: grams / 100)
  }

  /// Display values at `grams` converted back to per 100 g.
  public static func per100gFromDisplay(_ display: MacroTotals, grams: Double?) -> MacroTotals {
    guard let grams, grams > 0 else { return display }
    return display.scaled(by: 100 / grams)
  }

  /// Label overrides: edited macros at the current grams become the per-100 g base.
  public static func applyingEditedLabelMacros(
    to item: LogItem, edited: MacroTotals, grams: Double?
  ) -> LogItem {
    var updated = item
    updated.macroBasis = .per100g
    updated.baseGrams = 100
    updated.base = per100gFromDisplay(edited, grams: grams)
    let resolved = grams.flatMap { $0 > 0 ? $0 : nil } ?? validGrams(item.gramsText) ?? 100
    updated.gramsText = Macros.format(resolved, maxFractionDigits: 1)
    return updated
  }

  /// Ingredients for `save_meal` from the valid log items.
  public static func mealIngredients(from items: [LogItem]) -> [SavedMealIngredient] {
    items.compactMap { item in
      guard let grams = validGrams(item.gramsText), !item.name.trimmed.isEmpty,
        !item.isNutritionMissing
      else { return nil }
      return SavedMealIngredient(
        name: item.name.trimmed, grams: grams, macros: macros(item),
        linkedFoodId: item.linkedFoodId)
    }
  }

  // MARK: Quick log (5.9)

  /// Food: one item at `quantity` grams. Meal: each ingredient's grams × `quantity` portions.
  public static func quickLogItems(base: [LogItem], isMeal: Bool, quantity: Double) -> [LogItem] {
    base.map { item in
      var scaled = item
      let grams = isMeal ? (parseNumberInput(item.gramsText) ?? 0) * quantity : quantity
      scaled.gramsText = Macros.format(grams, maxFractionDigits: 1)
      return scaled
    }
  }

  /// Quantity > 0, every item in (0, 5000] grams, and no missing nutrition.
  public static func isQuickLogValid(items: [LogItem], quantity: Double?) -> Bool {
    guard let quantity, quantity > 0, !items.isEmpty else { return false }
    return items.allSatisfy { item in
      guard !item.isNutritionMissing, let grams = parseNumberInput(item.gramsText) else {
        return false
      }
      return grams > 0 && grams <= maxGrams
    }
  }
}

extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
  var nonEmpty: String? { isEmpty ? nil : self }
}
