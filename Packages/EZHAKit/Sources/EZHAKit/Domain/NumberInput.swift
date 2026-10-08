import Foundation

/// Port of `src/lib/number.ts`. Trim, remove spaces, accept a comma as the
/// decimal separator when there is no dot. Empty or non-finite input is nil.
public func parseNumberInput(_ text: String) -> Double? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  var normalized = trimmed.replacingOccurrences(of: " ", with: "")
    .replacingOccurrences(of: "\u{00A0}", with: "")
  if normalized.contains(","), !normalized.contains(".") {
    normalized = normalized.replacingOccurrences(of: ",", with: ".")
  }
  guard let value = Double(normalized), value.isFinite else { return nil }
  return value
}

/// Validation for editable values; parsing alone does not imply a valid portion.
public enum NumericInput {
  /// A generous entry limit, not a nutrition recommendation.
  public static let maxNutritionValue: Double = 100_000

  public static func portionError(_ text: String) -> String? {
    guard let value = parseNumberInput(text), value > 0, value <= LogItemMath.maxGrams else {
      return String(localized: "Enter a portion greater than 0 and no more than 5,000 g.")
    }
    return nil
  }

  public static func nutritionError(_ text: String) -> String? {
    guard let value = parseNumberInput(text), value >= 0, value <= maxNutritionValue else {
      return String(localized: "Enter a number from 0 to 100,000.")
    }
    return nil
  }
}
