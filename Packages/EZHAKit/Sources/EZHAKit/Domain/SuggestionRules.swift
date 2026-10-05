import Foundation

/// Port of the rules in `src/features/suggestions/SuggestionsPage.vue`.
public enum SuggestionRules {
  public enum MealType: String, CaseIterable, Codable, Sendable, Identifiable {
    case meal = "Meal"
    case snack = "Snack"
    public var id: String { rawValue }
  }

  public static let prepRange = 1...240
  public static let defaultPrepMinutes = 20
  public static let count = 3
  public static let units = "grams"
  public static let differentOptions = "Different options"
  public static let hint = "Consider halving the portion or choosing a lighter option."
  public static let noTargetsMessage = "Set your daily targets in Settings for better suggestions."

  public static func clampPrep(_ minutes: Int) -> Int {
    min(max(minutes, prepRange.lowerBound), prepRange.upperBound)
  }

  public static func adjustIngredientsNote(_ notes: String) -> String {
    "Adjust ingredients: \(notes.trimmed)"
  }

  public static func adjustPrepNote(_ minutes: Int) -> String {
    "Adjust prep time to \(clampPrep(minutes)) minutes"
  }

  /// "Exceeds calories by X kcal, protein by Y g, …" for each macro above remaining.
  public static func exceedWarning(_ suggestion: MacroTotals, remaining: MacroTotals) -> String? {
    var parts: [String] = []
    func over(_ value: Double, _ limit: Double) -> Int { Int((value - limit).rounded()) }
    if suggestion.calories > remaining.calories {
      parts.append("calories by \(over(suggestion.calories, remaining.calories)) kcal")
    }
    if suggestion.protein > remaining.protein {
      parts.append("protein by \(over(suggestion.protein, remaining.protein)) g")
    }
    if suggestion.carbs > remaining.carbs {
      parts.append("carbs by \(over(suggestion.carbs, remaining.carbs)) g")
    }
    if suggestion.fat > remaining.fat {
      parts.append("fat by \(over(suggestion.fat, remaining.fat)) g")
    }
    return parts.isEmpty ? nil : "Exceeds " + parts.joined(separator: ", ")
  }

  /// Shown when every goal is 0.
  public static func targetsHint(goals: MacroTotals) -> String? {
    goals.isAllZero ? noTargetsMessage : nil
  }

  /// Logger prefill for "Log this".
  public static func loggerText(for suggestion: MealSuggestion) -> String {
    "\(suggestion.title): \(suggestion.description)"
  }
}
