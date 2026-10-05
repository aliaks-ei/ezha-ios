import Foundation
import Testing

@testable import EZHAKit

struct LogItemMathTests {
  @Test func buildsLibraryFoodItemWithScaling() {
    let item = LogItemMath.fromSavedFood(sampleFood(), grams: 100)
    #expect(item.origin == .libraryFood)
    #expect(item.gramsText == "100")
    #expect(LogItemMath.macros(item) == MacroTotals(calories: 165, protein: 31, carbs: 0, fat: 3.6))
  }

  @Test func usesServingGramsForPerServingFoods() {
    let yogurt = sampleFood(
      name: "Yogurt", per100g: MacroTotals(calories: 200, protein: 20, carbs: 10, fat: 5),
      unitType: .perServing, servingSize: 150)
    let item = LogItemMath.fromSavedFood(yogurt)
    #expect(item.gramsText == "150")
    #expect(LogItemMath.macros(item).calories == 300)
    #expect(LogItemMath.defaultGrams(sampleFood(unitType: .perServing, servingSize: 0)) == 100)
  }

  @Test func keepsDuplicateAINamesAsSeparateRows() {
    let items = LogItemMath.fromEstimate(
      sampleEstimate(items: [
        .init(
          name: "Egg", grams: 50,
          macros: MacroTotals(calories: 78, protein: 6.3, carbs: 0.4, fat: 5.3)),
        .init(
          name: "egg", grams: 100,
          macros: MacroTotals(calories: 155, protein: 12.6, carbs: 0.8, fat: 10.6)),
      ]))
    #expect(items.map(\.name) == ["Egg", "egg"])
    #expect(items.map(\.gramsText) == ["50", "100"])
    #expect(isClose(LogItemMath.macros(items[0]).calories, 78))
    #expect(isClose(LogItemMath.macros(items[1]).fat, 10.6))
  }

  @Test func estimateWithoutItemsBecomesOneItemOf100g() {
    let item = LogItemMath.fromEstimate(sampleEstimate(items: []), fallbackName: "Soup")[0]
    #expect(item.name == "Chicken rice bowl")
    #expect(item.gramsText == "100")
    #expect(item.macroBasis == .perOriginal)
    #expect(LogItemMath.macros(item).calories == 520)
  }

  @Test func labelItemsArePer100gAtGramsEaten() {
    let items = LogItemMath.fromLabelEstimate(sampleEstimate(items: []), grams: 60)
    #expect(items[0].macroBasis == .per100g)
    #expect(items[0].gramsText == "60")
    #expect(isClose(LogItemMath.macros(items[0]).calories, 312))
    #expect(
      LogItemMath.fromLabelEstimate(sampleEstimate(items: []), grams: nil)[0].gramsText == "100")
  }

  @Test func scalesLabelsAndAppliesEditedMacros() {
    let per100 = MacroTotals(calories: 400, protein: 20, carbs: 60, fat: 10)
    #expect(
      LogItemMath.scalePer100g(per100, grams: 60)
        == MacroTotals(calories: 240, protein: 12, carbs: 36, fat: 6))
    let item = LogItem(
      name: "Label item", gramsText: "60", macroBasis: .per100g, baseGrams: 100, base: per100,
      origin: .ai)
    let edited = MacroTotals(calories: 210, protein: 14, carbs: 30, fat: 7)
    let updated = LogItemMath.applyingEditedLabelMacros(to: item, edited: edited, grams: 60)
    let macros = LogItemMath.macros(updated)
    #expect(isClose(macros.calories, 210) && isClose(macros.protein, 14))
    #expect(isClose(macros.carbs, 30) && isClose(macros.fat, 7))
  }

  @Test func expandsSavedMealsPer100gAndFlagsMissingNutrition() {
    let items = LogItemMath.fromSavedMeal([
      SavedMealIngredient(
        name: "Pasta", grams: 200,
        macros: MacroTotals(calories: 260, protein: 9, carbs: 51, fat: 1.3)),
      SavedMealIngredient(name: "Unknown", grams: 0, macros: .zero),
    ])
    var pasta = items[0]
    #expect(pasta.macroBasis == .per100g)
    pasta.gramsText = "300"
    #expect(isClose(LogItemMath.macros(pasta).calories, 390))
    #expect(isClose(LogItemMath.macros(pasta).carbs, 76.5))
    #expect(items[1].isNutritionMissing)
    #expect(LogItemMath.macros(items[1]) == .zero)
    #expect(EntryPayload.entryItems(entryId: UUID(), from: [items[1]]).isEmpty)
  }

  @Test func clampsGramsAndStepsBy5() {
    var item = LogItemMath.fromSavedFood(sampleFood())
    item.gramsText = "99999"
    #expect(LogItemMath.normalizedGrams(item.gramsText) == 5000)
    #expect(isClose(LogItemMath.macros(item).calories, 165 * 50))
    #expect(EntryPayload.entryItems(entryId: UUID(), from: [item])[0].grams == 5000)
    #expect(LogItemMath.validGrams("0") == nil)
    #expect(LogItemMath.step("100", by: 5) == ("105", false))
    #expect(LogItemMath.step("4998", by: 5) == ("5000", true))
    #expect(LogItemMath.step("3", by: -5) == ("0", false))
  }

  @Test func restoresTheLastValidGrams() {
    var item = LogItemMath.fromSavedFood(sampleFood(), grams: 120)
    item.gramsText = "abc"
    let foodId = item.linkedFoodId!
    #expect(
      LogItemMath.restoredGramsText(
        for: item, lastValidByItem: [item.id: "80"], lastValidByFood: [:]) == "80")
    #expect(
      LogItemMath.restoredGramsText(
        for: item, lastValidByItem: [:], lastValidByFood: [foodId: "90"]) == "90")
    #expect(
      LogItemMath.restoredGramsText(for: item, lastValidByItem: [:], lastValidByFood: [:]) == "100")
  }

  @Test func newEstimateReplacesOnlyAIItems() {
    let library = LogItemMath.fromSavedFood(sampleFood())
    let oldAI = LogItemMath.fromEstimate(sampleEstimate())
    let newAI = LogItemMath.fromEstimate(sampleEstimate(items: []))
    let result = LogItemMath.replacingAIItems(in: [library] + oldAI, with: newAI)
    #expect(result.map(\.id) == [library.id] + newAI.map(\.id))
  }

  @Test func buildsMealIngredientsWithLinkedIds() {
    let food = sampleFood()
    let libraryItem = LogItemMath.fromSavedFood(food, grams: 120)
    var aiItem = LogItemMath.fromEstimate(sampleEstimate(items: []))[0]
    aiItem.gramsText = "80"
    let ingredients = LogItemMath.mealIngredients(from: [libraryItem, aiItem])
    #expect(ingredients.map(\.grams) == [120, 80])
    #expect(ingredients[0].linkedFoodId == food.id)
    #expect(ingredients[1].linkedFoodId == nil)
    let sum = ingredients.reduce(MacroTotals.zero) { $0 + $1.macros }
    #expect(isClose(sum.calories, LogItemMath.totals([libraryItem, aiItem]).calories))
  }

  @Test func quickLogScalesFoodsByGramsAndMealsByPortions() {
    let food = LogItemMath.quickLogItems(
      base: [LogItemMath.fromSavedFood(sampleFood())], isMeal: false, quantity: 250)
    #expect(food[0].gramsText == "250")
    let meal = LogItemMath.quickLogItems(
      base: LogItemMath.fromSavedMeal([
        SavedMealIngredient(
          name: "Rice", grams: 200,
          macros: MacroTotals(calories: 260, protein: 5, carbs: 56, fat: 1))
      ]), isMeal: true, quantity: 1.5)
    #expect(meal[0].gramsText == "300")
    #expect(isClose(LogItemMath.totals(meal).calories, 390))
    #expect(LogItemMath.isQuickLogValid(items: meal, quantity: 1.5))
    #expect(!LogItemMath.isQuickLogValid(items: meal, quantity: 0))
    #expect(
      !LogItemMath.isQuickLogValid(
        items: LogItemMath.quickLogItems(base: meal, isMeal: true, quantity: 30), quantity: 30))
  }
}
