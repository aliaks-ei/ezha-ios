import Foundation
import Testing

@testable import EZHAKit

/// Millilitre items for drinks (PET-114).
struct AmountUnitTests {
  let beer = MacroTotals(calories: 43, protein: 0.5, carbs: 3.6, fat: 0)

  @Test func parsesMillilitreItemsAndDefaultsOldItemsToGrams() throws {
    let estimate = try Estimate.parse(
      Data(
        """
        {"totals":{"calories":141.9,"protein":1.65,"carbs":11.88,"fat":0},"source":"text",
         "notes":"","nutrition_basis":"per_portion",
         "items":[{"name":"Beer","grams":330,"unit":"ml","calories":141.9,"protein":1.65,
                   "carbs":11.88,"fat":0},
                  {"name":"Bread","grams":30,"calories":80,"protein":3,"carbs":15,"fat":1}]}
        """.utf8))
    #expect(estimate.items.map(\.unit) == [.ml, .g])
    let items = LogItemMath.fromEstimate(estimate)
    #expect(items.map(\.unit) == [.ml, .g])
    #expect(items[0].gramsText == "330")
  }

  @Test func scalesMillilitreItemsPer100ml() {
    var item = LogItem(
      name: "Beer", gramsText: "500", unit: .ml, macroBasis: .per100g, baseGrams: 100,
      base: beer, origin: .ai)
    #expect(isClose(LogItemMath.macros(item).calories, 215))
    #expect(isClose(LogItemMath.macros(item).carbs, 18))
    item.gramsText = "330"
    #expect(isClose(LogItemMath.totals([item]).calories, 141.9))
  }

  @Test func labelPer100mlKeepsTheUnit() {
    let estimate = Estimate(
      totals: beer, source: "label_photo",
      items: [.init(name: "Lager", grams: 100, unit: .ml, macros: beer)],
      nutritionBasis: .per100g)
    let items = LogItemMath.fromLabelEstimate(estimate, grams: 330)
    #expect(items[0].unit == .ml)
    #expect(isClose(LogItemMath.macros(items[0]).calories, 141.9))
  }

  @Test func payloadRowsAndMealIngredientsCarryTheUnit() throws {
    let item = LogItem(
      name: "Milk", gramsText: "250", unit: .ml, macroBasis: .per100g, baseGrams: 100,
      base: MacroTotals(calories: 64, protein: 3.3, carbs: 4.8, fat: 3.6), origin: .ai)
    let payload = EntryPayload.build(
      date: key("2026-11-06"), imagePath: nil, items: [item],
      sources: UsedSources(usedText: true), isLabelPhoto: false)
    #expect(payload.items[0].unit == .ml)
    #expect(payload.items[0].grams == 250)
    let json = try JSONSerialization.jsonObject(with: JSONEncoder.ezha.encode(payload.items[0]))
    #expect((json as? [String: Any])?["unit"] as? String == "ml")

    let ingredients = LogItemMath.mealIngredients(from: [item])
    #expect(ingredients[0].unit == .ml)
    let back = LogItemMath.fromSavedMeal(ingredients)
    #expect(back[0].unit == .ml)
    #expect(isClose(LogItemMath.macros(back[0]).calories, 160))
  }

  @Test func rowsWithoutUnitDecodeAsGrams() throws {
    let row = try JSONDecoder.ezha.decode(
      FoodEntryItem.self,
      from: Data(
        """
        {"id":"\(UUID())","entry_id":"\(UUID())","name":"Rice","grams":100,"calories":130,
         "protein":2.7,"carbs":28,"fat":0.3,"ai_notes":""}
        """.utf8))
    #expect(row.unit == .g)
    let food = try JSONDecoder.ezha.decode(
      SavedFood.self, from: Data(#"{"id":"\#(UUID())","name":"Juice","amount_unit":"ml"}"#.utf8))
    #expect(food.amountUnit == .ml)
    #expect(LogItemMath.fromSavedFood(food).unit == .ml)
    let old = try JSONDecoder.ezha.decode(
      SavedFood.self, from: Data(#"{"id":"\#(UUID())","name":"Rice"}"#.utf8))
    #expect(old.amountUnit == .g)
  }

  @Test func draftsWithoutUnitDecodeAsGrams() throws {
    let item = LogItem(
      name: "Rice", gramsText: "100", macroBasis: .per100g, baseGrams: 100, base: .zero,
      origin: .ai)
    var json = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
    json["unit"] = nil
    let decoded = try JSONDecoder().decode(
      LogItem.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.unit == .g)
    #expect(decoded == item)
  }

  @Test func manualDraftPer100mlEncodesTheUnit() throws {
    let draft = try LibraryDrafts.manualDraft(
      .init(
        name: "Oat drink", unitType: .perServing, servingGrams: 250, servingUnit: "glass",
        amountUnit: .ml, per100g: [46, 1, 6.7, 1.5])
    ).get()
    #expect(draft.amountUnit == .ml)
    #expect(isClose(draft.perServing.calories, 115))
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft))
    #expect((json as? [String: Any])?["amount_unit"] as? String == "ml")
    #expect(
      LibraryDrafts.manualDraft(
        .init(
          name: "Oat drink", unitType: .perServing, servingGrams: nil, servingUnit: "",
          amountUnit: .ml, per100g: [46, 1, 6.7, 1.5])) == .failure(.missingServingMl))
  }

  @Test func messagesUseTheUnit() {
    #expect(LogItemMath.maxAmountMessage(.ml) == "Max amount per item is 5000 ml.")
    #expect(NumericInput.portionError("0", unit: .ml)?.contains("ml") == true)
    #expect(AnalyzeGate.noItemsMessage == "Add at least one item with an amount before logging.")
    #expect(AmountUnit.ml.format(330) == "330 ml")
  }
}
