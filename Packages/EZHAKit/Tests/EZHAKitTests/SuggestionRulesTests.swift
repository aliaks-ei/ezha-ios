import Testing

@testable import EZHAKit

struct SuggestionRulesTests {
  let remaining = MacroTotals(calories: 500, protein: 30, carbs: 50, fat: 20)

  @Test func warnsForEachExceededMacro() {
    let all = MacroTotals(calories: 620.4, protein: 45, carbs: 70.6, fat: 25)
    #expect(
      SuggestionRules.exceedWarning(all, remaining: remaining)
        == "Exceeds calories by 120 kcal, protein by 15 g, carbs by 21 g, fat by 5 g")
    #expect(
      SuggestionRules.exceedWarning(
        MacroTotals(calories: 400, protein: 40, carbs: 10, fat: 5), remaining: remaining)
        == "Exceeds protein by 10 g")
    #expect(
      SuggestionRules.exceedWarning(
        MacroTotals(calories: 400, protein: 20, carbs: 10, fat: 5), remaining: remaining) == nil)
  }

  @Test func clampsPrepAndBuildsVariationNotes() {
    #expect(SuggestionRules.clampPrep(0) == 1)
    #expect(SuggestionRules.clampPrep(300) == 240)
    #expect(SuggestionRules.clampPrep(20) == 20)
    #expect(SuggestionRules.adjustPrepNote(500) == "Adjust prep time to 240 minutes")
    #expect(SuggestionRules.adjustIngredientsNote(" no nuts ") == "Adjust ingredients: no nuts")
    #expect(SuggestionRules.differentOptions == "Different options")
  }

  @Test func hintsWhenAllGoalsAreZero() {
    #expect(SuggestionRules.targetsHint(goals: .zero) == SuggestionRules.noTargetsMessage)
    #expect(SuggestionRules.targetsHint(goals: remaining) == nil)
  }
}
