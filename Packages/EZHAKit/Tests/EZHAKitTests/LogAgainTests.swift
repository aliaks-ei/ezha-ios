import Foundation
import Testing

@testable import EZHAKit

struct LogAgainTests {
  private func sampleEntry() -> DayEntry {
    let id = UUID()
    let rice = FoodEntryItem(
      id: UUID(), entryId: id, name: "Rice", grams: 200,
      macros: MacroTotals(calories: 260, protein: 5, carbs: 56, fat: 0.6), aiConfidence: 0.8,
      aiNotes: "AI")
    let milk = FoodEntryItem(
      id: UUID(), entryId: id, name: "Milk", grams: 250, unit: .ml,
      macros: MacroTotals(calories: 125, protein: 8, carbs: 12, fat: 5), aiConfidence: nil,
      aiNotes: "")
    let empty = FoodEntryItem(
      id: UUID(), entryId: id, name: "Water", grams: 0, macros: .zero, aiConfidence: nil,
      aiNotes: "")
    let entry = FoodEntry(
      id: id, date: key("2026-10-04"), inputType: .text, inputText: "Rice and milk",
      imagePath: "u/e.jpg", macros: MacroTotals(calories: 385, protein: 13, carbs: 68, fat: 5.6),
      aiConfidence: 0.8, aiSource: .text, aiNotes: "notes", createdAt: .distantPast)
    return DayEntry(entry: entry, items: [rice, milk, empty])
  }

  @Test func itemsKeepAmountsAndSkipZeroGrams() {
    let items = LogAgain.items(from: sampleEntry())
    #expect(items.map(\.name) == ["Rice", "Milk"])
    #expect(items.map(\.gramsText) == ["200", "250"])
    #expect(items[1].unit == .ml)
    #expect(isClose(LogItemMath.totals(items).calories, 385))
    #expect(LogAgain.isValid(items))
  }

  @Test func payloadUsesNewIdsChosenDateAndScaledMacros() {
    let entry = sampleEntry()
    var items = LogAgain.items(from: entry)
    items[0].gramsText = "100"
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let payload = LogAgain.payload(
      from: entry, items: items, date: key("2026-10-07"), createdAt: now)

    #expect(payload.entry.id != entry.id)
    #expect(payload.entry.date == key("2026-10-07"))
    #expect(payload.entry.createdAt == now)
    #expect(payload.entry.inputText == "Rice and milk")
    #expect(payload.entry.imagePath == "u/e.jpg")
    #expect(payload.items.count == 2)
    #expect(payload.items.allSatisfy { $0.entryId == payload.entry.id })
    #expect(Set(payload.items.map(\.id)).isDisjoint(with: entry.items.map(\.id)))
    #expect(payload.items[0].grams == 100)
    #expect(isClose(payload.items[0].calories, 130))
    #expect(isClose(payload.items[0].carbs, 28))
    #expect(payload.items[1].unit == .ml)
    #expect(isClose(payload.entry.calories, 255))
    #expect(isClose(payload.entry.protein, 10.5))
  }

  @Test func zeroOrEmptyAmountIsInvalid() {
    var items = LogAgain.items(from: sampleEntry())
    items[0].gramsText = "0"
    #expect(!LogAgain.isValid(items))
    items[0].gramsText = ""
    #expect(!LogAgain.isValid(items))
    items[0].gramsText = "5001"
    #expect(!LogAgain.isValid(items))
    #expect(!LogAgain.isValid([]))
  }
}
