import Foundation
import Testing

@testable import EZHAKit

struct LibraryDraftsTests {
  @Test func buildsAPhotoDraftPer100g() throws {
    let draft = try LibraryDrafts.photoDraft(
      name: " Soup ", display: [120, 8, 10, 4], isLabelPhoto: false, labelGrams: nil
    ).get()
    #expect(draft.name == "Soup")
    #expect(draft.unitType == .per100g)
    #expect(draft.per100g == MacroTotals(calories: 120, protein: 8, carbs: 10, fat: 4))
    #expect(draft.perServing == .zero)
  }

  @Test func convertsLabelDisplayBackToPer100g() throws {
    let draft = try LibraryDrafts.photoDraft(
      name: "Granola", display: [200, 5, 30, 7.5], isLabelPhoto: true, labelGrams: 50
    ).get()
    #expect(isClose(draft.per100g.calories, 400) && isClose(draft.per100g.protein, 10))
    #expect(isClose(draft.per100g.carbs, 60) && isClose(draft.per100g.fat, 15))
  }

  @Test func computesPerServingFromPer100g() throws {
    let draft = try LibraryDrafts.manualDraft(
      .init(
        name: "Yogurt", unitType: .perServing, servingGrams: 150, servingUnit: " ",
        per100g: [60, 10, 4, 0.4])
    ).get()
    #expect(draft.servingSize == 150)
    #expect(draft.servingUnit == "serving")
    #expect(isClose(draft.perServing.calories, 90) && isClose(draft.perServing.protein, 15))
  }

  @Test func returnsValidationErrors() {
    func manual(_ name: String, _ unit: FoodUnitType, _ grams: Double?, _ macros: [Double?])
      -> LibraryDraftError?
    {
      if case .failure(let error) = LibraryDrafts.manualDraft(
        .init(name: name, unitType: unit, servingGrams: grams, servingUnit: "", per100g: macros))
      {
        return error
      }
      return nil
    }
    #expect(manual(" ", .per100g, nil, [1, 1, 1, 1]) == .missingName)
    #expect(manual("A", .per100g, nil, [1, nil, 1, 1]) == .invalidMacros)
    #expect(manual("A", .perServing, 0, [1, 1, 1, 1]) == .missingServing)
    #expect(manual("A", .per100g, nil, [1, 1, 1, 1]) == nil)
  }

  @Test func findsExactCaseInsensitiveDuplicatesAmongFoods() {
    let foods = [
      sampleFood(name: "Rice Bowl", isMeal: true), sampleFood(name: "Greek Yogurt"),
    ]
    #expect(LibraryDrafts.duplicate(of: " greek yogurt ", in: foods)?.name == "Greek Yogurt")
    #expect(LibraryDrafts.duplicate(of: "rice bowl", in: foods) == nil)
    #expect(LibraryDrafts.duplicate(of: "Greek", in: foods) == nil)
  }

  @Test func suggestsALibraryName() {
    #expect(
      LibraryDrafts.suggestedName(
        selectedLibraryFoodName: " Oats ", itemNames: ["A"], descriptionText: "d", aiFoodName: "x")
        == "Oats")
    #expect(
      LibraryDrafts.suggestedName(
        selectedLibraryFoodName: nil, itemNames: ["Rice", " ", "Egg"], descriptionText: "d",
        aiFoodName: nil) == "Rice + Egg")
    #expect(
      LibraryDrafts.suggestedName(
        selectedLibraryFoodName: nil, itemNames: [], descriptionText: " soup ", aiFoodName: "x")
        == "soup")
    #expect(
      LibraryDrafts.suggestedName(
        selectedLibraryFoodName: "", itemNames: [], descriptionText: "", aiFoodName: "Bowl")
        == "Bowl")
  }
}
