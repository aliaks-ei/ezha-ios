import Foundation
import Testing

@testable import EZHAKit

/// PET-115: fiber is optional display data. Unknown (nil) never becomes 0.
struct FiberTests {
  private func macros(_ fiber: Double?) -> MacroTotals {
    MacroTotals(calories: 100, protein: 5, carbs: 10, fat: 2, fiber: fiber)
  }

  @Test func sumsKnownFiberAndKeepsUnknownUnknown() {
    #expect((macros(nil) + macros(nil)).fiber == nil)
    #expect((macros(2) + macros(nil)).fiber == 2)
    #expect((macros(2) + macros(0)).fiber == 2)
    #expect((MacroTotals.zero + macros(3)).fiber == 3)
    #expect(macros(nil).scaled(by: 2).fiber == nil)
    #expect(macros(2.5).scaled(by: 2).fiber == 5)
    #expect(macros(2.6).rounded.fiber == 3)
  }

  @Test func decodesRowsWithoutFiberAsUnknown() throws {
    let item = """
      {"id": "\(UUID())", "entry_id": "\(UUID())", "name": "Soup", "grams": 300,
       "calories": 200, "protein": 5, "carbs": 20, "fat": 8, "ai_notes": ""}
      """
    let decoded = try JSONDecoder.ezha.decode(FoodEntryItem.self, from: Data(item.utf8))
    #expect(decoded.fiber == nil)
    let withFiber = item.replacingOccurrences(of: "\"fat\": 8", with: "\"fat\": 8, \"fiber\": 4")
    #expect(try JSONDecoder.ezha.decode(FoodEntryItem.self, from: Data(withFiber.utf8)).fiber == 4)
    let totals = try JSONDecoder().decode(
      MacroTotals.self, from: Data(#"{"calories": 1, "protein": 1, "carbs": 1, "fat": 1}"#.utf8))
    #expect(totals.fiber == nil)
    let food = try JSONDecoder.ezha.decode(
      SavedFood.self,
      from: Data(#"{"id": "\#(UUID())", "name": "Oats", "fiber_per_100g": 10.1}"#.utf8))
    #expect(food.per100g.fiber == 10.1)
    #expect(food.perServing.fiber == nil)
  }

  @Test func itemsWithoutFiberOmitTheKeyAndDraftsSendNull() throws {
    let item = FoodEntryItem(
      id: UUID(), entryId: UUID(), name: "Soup", grams: 300, macros: macros(nil),
      aiConfidence: nil, aiNotes: "")
    let json = String(decoding: try JSONEncoder.ezha.encode(item), as: UTF8.self)
    #expect(!json.contains("fiber"))
    let draft = SavedFoodDraft(
      name: "Oats", unitType: .per100g, servingSize: nil, servingUnit: nil, per100g: macros(nil),
      perServing: .zero)
    let body = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(draft))
    // Null clears a value that an edit removed.
    #expect((body as? [String: Any])?["fiber_per_100g"] is NSNull)
  }

  @Test func daySummaryTellsCompletePartialAndUnknownApart() {
    func entry(_ items: [Double?]) -> DayEntry {
      let id = UUID()
      let rows = items.map {
        FoodEntryItem(
          id: UUID(), entryId: id, name: "Food", grams: 100, macros: macros($0),
          aiConfidence: nil, aiNotes: "")
      }
      let total = rows.reduce(MacroTotals.zero) { $0 + $1.macros }
      return DayEntry(
        entry: FoodEntry(
          id: id, date: key("2026-11-06"), inputType: .text, inputText: "Meal", imagePath: nil,
          macros: total, aiConfidence: nil, aiSource: .text, aiNotes: "", createdAt: nil),
        items: rows)
    }
    #expect(FiberSummary.day([]) == FiberSummary(grams: 0, unknownMeals: 0))
    #expect(FiberSummary.day([]).isComplete)
    let complete = FiberSummary.day([entry([9]), entry([4, 0])])
    #expect(complete == FiberSummary(grams: 13, unknownMeals: 0) && complete.isComplete)
    // A meal with one unknown food still adds its known foods; the total is a lower bound.
    let partial = FiberSummary.day([entry([9]), entry([4, nil]), entry([nil])])
    #expect(partial == FiberSummary(grams: 13, unknownMeals: 2) && !partial.isComplete)
    let unknown = FiberSummary.day([entry([nil]), entry([nil, nil])])
    #expect(unknown == FiberSummary(grams: nil, unknownMeals: 2))
  }

  @Test func logItemsScaleFiberIntoTheEntry() {
    var oats = sampleFood(name: "Oats", per100g: macros(10))
    oats.fiberPer100g = 10
    let food = LogItemMath.fromSavedFood(oats, grams: 50)
    #expect(LogItemMath.macros(food).fiber == 5)
    let soup = LogItem(
      name: "Soup", gramsText: "300", macroBasis: .perOriginal, baseGrams: 300, base: macros(nil),
      origin: .ai)
    #expect(LogItemMath.macros(soup).fiber == nil)
    let payload = EntryPayload.build(
      date: key("2026-11-06"), imagePath: nil, items: [food, soup], sources: UsedSources(),
      isLabelPhoto: false)
    #expect(payload.items.map(\.fiber) == [5, nil])
    #expect(payload.entry.fiber == 5)
    let meal = LogItemMath.mealIngredients(from: [food, soup])
    #expect(meal.map(\.fiber) == [5, nil])
    #expect(LogItemMath.fromSavedMeal(meal).map { LogItemMath.macros($0).fiber } == [5, nil])
  }

  @Test func resolvesPer100gFiberFromAServing() {
    var bar = sampleFood(
      name: "Bar", per100g: .zero, unitType: .perServing, servingSize: 40)
    bar.caloriesPerServing = 160
    bar.fiberPerServing = 2
    #expect(Macros.resolvedPer100g(bar).fiber == 5)
  }

  @Test func estimatesKeepValidFiberOnly() throws {
    let json = """
      {"source": "text", "notes": "", "nutrition_basis": "per_portion",
       "totals": {"calories": 300, "protein": 10, "carbs": 40, "fat": 8, "fiber": null},
       "items": [
        {"name": "Rice", "grams": 180, "calories": 234, "protein": 5, "carbs": 50, "fat": 1,
         "fiber": 0.72},
        {"name": "Sauce", "grams": 30, "calories": 66, "protein": 5, "carbs": 0, "fat": 7,
         "fiber": -3},
        {"name": "Tea", "grams": 200, "calories": 0, "protein": 0, "carbs": 0, "fat": 0}
       ]}
      """
    let estimate = try Estimate.parse(Data(json.utf8))
    #expect(estimate.items.map(\.fiber) == [0.72, nil, nil])
    #expect(LogItemMath.fromEstimate(estimate).map(\.base.fiber) == [0.72, nil, nil])
  }

  @Test func libraryDraftsTakeOptionalFiber() throws {
    func manual(_ fiber: FiberInput) -> Result<SavedFoodDraft, LibraryDraftError> {
      LibraryDrafts.manualDraft(
        .init(
          name: "Oats", unitType: .perServing, servingGrams: 40, servingUnit: "cup",
          per100g: [379, 13, 68, 6.5], fiber: fiber))
    }
    #expect(try manual(.unknown).get().per100g.fiber == nil)
    #expect(try manual(.text("  ")).get().per100g.fiber == nil)
    let draft = try manual(.text("10,5")).get()
    #expect(draft.per100g.fiber == 10.5)
    #expect(isClose(draft.perServing.fiber ?? 0, 4.2))
    #expect(try manual(.text("0")).get().per100g.fiber == 0)
    #expect(throws: LibraryDraftError.invalidFiber) { try manual(.text("abc")).get() }
    #expect(throws: LibraryDraftError.invalidFiber) { try manual(.text("-1")).get() }
    let label = try LibraryDrafts.photoDraft(
      name: "Granola", display: [200, 5, 30, 7.5], isLabelPhoto: true, labelGrams: 50,
      fiber: .text("3")
    ).get()
    #expect(label.per100g.fiber == 6)
  }
}
