import Foundation
import Testing

@testable import EZHAKit

struct MenuSuggestionsTests {
  let goals = MacroTotals(calories: 2000, protein: 120, carbs: 200, fat: 70)
  let remaining = MacroTotals(calories: 650, protein: 40, carbs: 70, fat: 20)

  private func line(_ calories: Double, _ protein: Double, _ carbs: Double, _ fat: Double)
    -> String?
  {
    SuggestionRules.impactLine(
      MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat),
      remaining: remaining, goals: goals)
  }

  @Test func impactLineShowsWhatIsLeftReachedAndOver() {
    #expect(line(480, 42, 18, 24) == "Leaves 170 kcal · Protein goal reached · Fat 4 g over")
    #expect(
      line(980, 52, 70, 54)
        == "330 kcal over · Protein 12 g over · Carbs goal reached · Fat 34 g over")
  }

  @Test func impactLineShowsProteinToGoWhenNothingIsReached() {
    #expect(line(300, 10, 30, 8) == "Leaves 350 kcal · 30 g protein to go")
  }

  @Test func caloriesWithinFivePercentOfTheGoalCountAsReached() {
    #expect(line(640, 10, 30, 8) == "Calorie goal reached · 30 g protein to go")
    #expect(line(740, 10, 30, 8) == "Calorie goal reached · 30 g protein to go")
    #expect(line(760, 10, 30, 8) == "110 kcal over · 30 g protein to go")
  }

  @Test func impactLineSkipsMacrosWithoutGoalsOrWithoutThisDish() {
    #expect(SuggestionRules.impactLine(.example, remaining: remaining, goals: .zero) == nil)
    let caloriesOnly = MacroTotals(calories: 2000, protein: 0, carbs: 0, fat: 0)
    #expect(
      SuggestionRules.impactLine(
        MacroTotals(calories: 300, protein: 10, carbs: 30, fat: 8), remaining: remaining,
        goals: caloriesOnly) == "Leaves 350 kcal")
    // Fat is already over, but this dish adds none, so it is not repeated.
    let overFat = MacroTotals(calories: 650, protein: 40, carbs: 70, fat: -5)
    #expect(
      SuggestionRules.impactLine(
        MacroTotals(calories: 200, protein: 10, carbs: 40, fat: 0), remaining: overFat, goals: goals
      )
        == "Leaves 450 kcal · 30 g protein to go")
  }

  @Test func menuPrefillNamesTheDishAsARestaurantPortion() {
    let dish = PreviewData.menuSuggestions[0]
    #expect(
      SuggestionRules.menuLoggerText(for: dish)
        == "Grilled chicken Caesar (restaurant): Chicken breast, romaine, parmesan, about 350 g.")
    var bare = dish
    bare.description = "  "
    #expect(SuggestionRules.menuLoggerText(for: bare) == "Grilled chicken Caesar (restaurant)")
  }

  @Test func requestEncodesPhotosAsBase64AndOmitsBlankPreferences() throws {
    let photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
    let request = MenuSuggestionsRequest(
      remaining: remaining, mealType: .snack, preferences: "  ", variationNote: nil,
      photos: [photo, photo])
    let json = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    #expect(json["meal_type"] as? String == "Snack")
    #expect(json["images"] as? [String] == ["/9j/4A==", "/9j/4A=="])
    #expect(json["preferences"] == nil)
    #expect(json["variation_note"] == nil)
    #expect((json["remaining"] as? [String: Any])?["calories"] as? Double == 650)
  }

  @Test func parsesMenuFieldsAndKeepsFiveSuggestions() throws {
    let item =
      #"{"title":"Soup","description":"A bowl.","calories":300,"protein":8,"carbs":40,"fat":10,"menu_section":"Starters","order_tip":"Skip the bread."}"#
    let data = Data(
      #"{"suggestions":[\#(Array(repeating: item, count: 6).joined(separator: ","))]}"#.utf8)
    let list = try MealSuggestion.parse(data, limit: SuggestionRules.menuCount)
    #expect(list.count == 5)
    #expect(list[0].menuSection == "Starters")
    #expect(list[0].orderTip == "Skip the bread.")
    #expect(try MealSuggestion.parse(data).count == SuggestionRules.count)
  }

  @Test func olderSuggestionsWithoutMenuFieldsStillParse() throws {
    let list = try MealSuggestion.parse(
      Data(
        #"{"suggestions":[{"title":"Wrap","description":"Turkey.","calories":400,"protein":30,"carbs":40,"fat":12,"menu_section":null}]}"#
          .utf8))
    #expect(list[0].menuSection == nil)
    #expect(list[0].orderTip == nil)
  }
}
