import Foundation
import Testing

@testable import EZHAKit

struct MacrosTests {
  @Test func reportsPercentAndCapsTheBar() {
    #expect(Macros.progressPercent(eaten: 1500, target: 2000) == 75)
    #expect(Macros.progressPercent(eaten: 2250, target: 2000) == 113)
    #expect(Macros.barPercent(eaten: 2250, target: 2000) == 100)
  }

  @Test func returnsZeroWhenTargetIsNotSet() {
    #expect(Macros.progressPercent(eaten: 400, target: 0) == 0)
    #expect(Macros.barPercent(eaten: 400, target: 0) == 0)
  }

  @Test func sumsDayTotalsRoundedAndRemainingUnclamped() {
    let entries = [600.4, 250.3].map {
      FoodEntry(
        id: UUID(), date: key("2026-10-05"), inputType: .text, inputText: nil, imagePath: nil,
        macros: MacroTotals(calories: $0, protein: 10.4, carbs: 20.3, fat: 5.3),
        aiConfidence: nil, aiSource: .text, aiNotes: "", createdAt: nil)
    }
    let totals = Macros.dayTotals(entries)
    #expect(totals == MacroTotals(calories: 851, protein: 21, carbs: 41, fat: 11))
    let remaining = Macros.remaining(
      goals: MacroTotals(calories: 800, protein: 140, carbs: 220, fat: 70), totals: totals)
    #expect(remaining.calories == -51)
    #expect(Macros.calorieStatus(goal: 800, eaten: 851) == (51, true))
    #expect(Macros.calorieStatus(goal: 2100, eaten: 640) == (1460, false))
  }

  @Test func derivesPer100gFromPerServingOnlyFoods() {
    let food = SavedFood(
      id: UUID(), name: "Bar", unitType: .perServing, servingSize: 50,
      perServing: MacroTotals(calories: 200, protein: 10, carbs: 20, fat: 8))
    #expect(
      Macros.resolvedPer100g(food) == MacroTotals(calories: 400, protein: 20, carbs: 40, fat: 16))
    let per100Only = sampleFood(unitType: .perServing, servingSize: 200)
    #expect(Macros.resolvedPerServing(per100Only).calories == 330)
    #expect(Macros.resolvedPer100g(SavedFood(id: UUID(), name: "Empty")) == .zero)
  }

  @Test func formatsWithoutGrouping() {
    #expect(Macros.format(12345.678, maxFractionDigits: 1) == "12345.7")
    #expect(Macros.format(100, maxFractionDigits: 2) == "100")
  }
}
