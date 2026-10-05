import Foundation

@testable import EZHAKit

let pacific: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
  return calendar
}()

func key(_ string: String) -> DateKey { DateKey(string, calendar: pacific)! }

func sampleFood(
  id: UUID = UUID(), name: String = "Chicken Breast", isMeal: Bool = false,
  per100g: MacroTotals = MacroTotals(calories: 165, protein: 31, carbs: 0, fat: 3.6),
  unitType: FoodUnitType = .per100g, servingSize: Double? = nil, isFavorite: Bool = false,
  lastUsedAt: Date? = nil
) -> SavedFood {
  SavedFood(
    id: id, name: name, unitType: unitType, servingSize: servingSize, per100g: per100g,
    isMeal: isMeal, isFavorite: isFavorite, lastUsedAt: lastUsedAt)
}

func sampleEstimate(items: [Estimate.Item]? = nil) -> Estimate {
  Estimate(
    totals: MacroTotals(calories: 520, protein: 30, carbs: 56, fat: 20), confidence: 0.88,
    source: "text", foodName: "Chicken rice bowl", notes: "AI estimate",
    items: items ?? [
      .init(
        name: "Chicken", grams: 150,
        macros: MacroTotals(calories: 247.5, protein: 46.5, carbs: 0, fat: 5.4), confidence: 0.9),
      .init(
        name: "Rice", grams: 180,
        macros: MacroTotals(calories: 272.5, protein: 3.5, carbs: 56, fat: 14.6), confidence: 0.86),
    ])
}

func isClose(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }
