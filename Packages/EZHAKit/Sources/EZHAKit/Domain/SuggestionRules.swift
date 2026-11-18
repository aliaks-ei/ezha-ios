import Foundation

/// Port of the rules in `src/features/suggestions/SuggestionsPage.vue`.
public enum SuggestionRules {
  public enum MealType: String, CaseIterable, Codable, Sendable, Identifiable {
    case meal = "Meal"
    case snack = "Snack"
    public var id: String { rawValue }
  }

  /// Cook: ideas to make at home. Eat out: dishes from restaurant menu photos.
  public enum Mode: String, CaseIterable, Sendable, Identifiable {
    case cook
    case eatOut
    public var id: String { rawValue }
  }

  public static let prepRange = 1...240
  public static let defaultPrepMinutes = 20
  public static let count = 3
  public static let menuCount = 5
  public static let maxMenuPhotos = 4
  /// A macro within this share of its goal counts as reached.
  public static let goalTolerance = 0.05
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

  /// Logger prefill for + on a menu dish. The portion note helps the estimate.
  public static func menuLoggerText(for suggestion: MealSuggestion) -> String {
    let description = suggestion.description.trimmed
    return description.isEmpty
      ? "\(suggestion.title) (restaurant)"
      : "\(suggestion.title) (restaurant): \(description)"
  }

  /// What ordering a dish does to the day, for example
  /// "Leaves 420 kcal · Protein goal reached · Fat 6 g over".
  /// Calories always show. Protein, carbs, and fat show only when the dish brings them within
  /// 5% of the goal ("goal reached") or past it ("over"). When none do, protein still to go shows.
  /// Nil when no targets are set.
  public static func impactLine(
    _ dish: MacroTotals, remaining: MacroTotals, goals: MacroTotals
  ) -> String? {
    guard !goals.isAllZero else { return nil }
    func whole(_ value: Double) -> Int { Int(value.rounded()) }
    func tolerance(_ goal: Double, minimum: Double) -> Double {
      max(goal * goalTolerance, minimum)
    }
    var parts: [String] = []
    if goals.calories > 0 {
      let after = remaining.calories - dish.calories
      if abs(after) <= tolerance(goals.calories, minimum: 10) {
        parts.append("Calorie goal reached")
      } else if after > 0 {
        parts.append("Leaves \(whole(after)) kcal")
      } else {
        parts.append("\(whole(-after)) kcal over")
      }
    }
    let macros: [(name: String, goal: Double, remaining: Double, dish: Double)] = [
      ("Protein", goals.protein, remaining.protein, dish.protein),
      ("Carbs", goals.carbs, remaining.carbs, dish.carbs),
      ("Fat", goals.fat, remaining.fat, dish.fat),
    ]
    var changed = false
    for macro in macros where macro.goal > 0 && macro.dish > 0 {
      let after = macro.remaining - macro.dish
      let slack = tolerance(macro.goal, minimum: 1)
      if after < -slack {
        parts.append("\(macro.name) \(whole(-after)) g over")
        changed = true
      } else if after <= slack {
        parts.append("\(macro.name) goal reached")
        changed = true
      }
    }
    if !changed, goals.protein > 0 {
      let toGo = remaining.protein - dish.protein
      if toGo >= 1 { parts.append("\(whole(toGo)) g protein to go") }
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}
