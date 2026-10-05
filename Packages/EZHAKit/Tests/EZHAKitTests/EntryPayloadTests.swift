import Foundation
import Testing

@testable import EZHAKit

struct EntryPayloadTests {
  let date = key("2026-03-09")

  @Test(arguments: [
    (UsedSources(usedPhoto: true, usedText: true), false, InputType.photoText, AISource.foodPhoto),
    (
      UsedSources(usedPhoto: true, usedText: true, usedLibrary: true), true, .photoText, .labelPhoto
    ),
    (UsedSources(usedPhoto: true), false, .photo, .foodPhoto),
    (UsedSources(usedPhoto: true), true, .photo, .labelPhoto),
    (UsedSources(usedText: true), false, .text, .text),
    (UsedSources(usedText: true, usedLibrary: true), false, .text, .text),
    (UsedSources(usedLibrary: true), false, .text, .library),
    (UsedSources(), false, .text, .unknown),
  ])
  func resolvesSourceMetadata(
    sources: UsedSources, isLabel: Bool, inputType: InputType, aiSource: AISource
  ) {
    let result = EntryPayload.resolveInput(sources, isLabelPhoto: isLabel)
    #expect(result.inputType == inputType)
    #expect(result.aiSource == aiSource)
  }

  @Test func resolvesAnalyzeInputType() {
    #expect(EntryPayload.analyzeInputType(hasPhoto: true, isLabelPhoto: false) == "food_photo")
    #expect(EntryPayload.analyzeInputType(hasPhoto: true, isLabelPhoto: true) == "label_photo")
    #expect(EntryPayload.analyzeInputType(hasPhoto: false, isLabelPhoto: true) == "text")
  }

  @Test func buildsAPhotoPayload() {
    let payload = EntryPayload.build(
      date: date, imagePath: "u/e.jpg", items: LogItemMath.fromEstimate(sampleEstimate()),
      sources: UsedSources(usedPhoto: true), isLabelPhoto: false)
    #expect(payload.entry.inputType == .photo)
    #expect(payload.entry.aiSource == .foodPhoto)
    #expect(payload.entry.imagePath == "u/e.jpg")
    #expect(payload.entry.inputText == "Chicken, Rice")
    #expect(payload.items.count == 2)
    #expect(isClose(payload.entry.aiConfidence ?? 0, 0.88))
    #expect(payload.entry.aiNotes == "Logged from combined meal sources")
    #expect(isClose(payload.entry.calories, 520))
  }

  @Test func buildsALibraryPayloadWithUsedFoodIds() {
    let food = sampleFood()
    let mealId = UUID()
    let payload = EntryPayload.build(
      date: date, imagePath: nil, items: [LogItemMath.fromSavedFood(food)],
      sources: UsedSources(usedLibrary: true), isLabelPhoto: false, extraUsedFoodIds: [mealId])
    #expect(payload.entry.inputType == .text)
    #expect(payload.entry.aiSource == .library)
    #expect(payload.entry.inputText == "Chicken Breast")
    #expect(payload.entry.aiConfidence == nil)
    #expect(payload.usedFoodIds == [food.id, mealId])
  }

  @Test func joinsNamesOrFallsBackToMeal() {
    let rows = EntryPayload.entryItems(
      entryId: UUID(),
      from: [
        LogItemMath.fromSavedFood(sampleFood()),
        LogItemMath.fromEstimate(sampleEstimate(items: []))[0],
      ])
    #expect(EntryPayload.inputText(rows) == "Chicken Breast, Chicken rice bowl")
    #expect(EntryPayload.inputText([]) == "Meal")
  }

  @Test func skipsItemsWithoutNameOrGrams() {
    var noName = LogItemMath.fromSavedFood(sampleFood())
    noName.name = "  "
    var noGrams = LogItemMath.fromSavedFood(sampleFood())
    noGrams.gramsText = "0"
    #expect(EntryPayload.entryItems(entryId: UUID(), from: [noName, noGrams]).isEmpty)
  }

  @Test func gatesEstimateVersusLog() {
    let a = AnalyzeGate.Fingerprint(text: " rice ", photoId: nil, isLabel: false)
    let b = AnalyzeGate.Fingerprint(text: "rice", photoId: nil, isLabel: false)
    let changed = AnalyzeGate.Fingerprint(text: "rice", photoId: "p1", isLabel: false)
    let empty = AnalyzeGate.Fingerprint(text: "", photoId: nil, isLabel: false)
    #expect(AnalyzeGate.primaryAction(current: a, lastAnalyzed: nil) == .estimate)
    #expect(AnalyzeGate.primaryAction(current: a, lastAnalyzed: b) == .log)
    #expect(AnalyzeGate.primaryAction(current: changed, lastAnalyzed: b) == .estimate)
    #expect(AnalyzeGate.isStale(current: changed, lastAnalyzed: b))
    #expect(!AnalyzeGate.isStale(current: a, lastAnalyzed: nil))
    #expect(AnalyzeGate.primaryAction(current: empty, lastAnalyzed: nil) == .log)
  }

  @Test func blocksLoggingWithMissingNutritionOrNoItems() {
    let missing = LogItemMath.fromSavedMeal([
      SavedMealIngredient(
        name: "X", grams: 100, macros: MacroTotals(calories: .nan, protein: 0, carbs: 0, fat: 0))
    ])
    #expect(
      AnalyzeGate.logBlockReason(missing + [LogItemMath.fromSavedFood(sampleFood())])
        == AnalyzeGate.missingNutritionMessage)
    #expect(AnalyzeGate.logBlockReason([]) == AnalyzeGate.noItemsMessage)
    #expect(AnalyzeGate.logBlockReason([LogItemMath.fromSavedFood(sampleFood())]) == nil)
  }
}
