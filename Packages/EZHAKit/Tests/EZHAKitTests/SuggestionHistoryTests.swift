import Foundation
import Testing

@testable import EZHAKit

struct SuggestionHistoryTests {
  let start = Date(timeIntervalSince1970: 1_800_000_000)
  let day: TimeInterval = 24 * 60 * 60

  @Test func keepsNewestFirstWithoutDuplicates() {
    var history = SuggestionHistory()
    history.record(["Chicken salad bowl", "Greek yogurt and berries", "  "], at: start)
    history.record(["Tofu stir-fry", "chicken salad bowl"], at: start + 60)
    #expect(
      history.titles(now: start + 120) == [
        "Tofu stir-fry", "chicken salad bowl", "Greek yogurt and berries",
      ])
  }

  @Test func dropsTitlesOlderThanAWeek() {
    var history = SuggestionHistory()
    history.record(["Old bowl"], at: start)
    history.record(["New wrap"], at: start + 6 * day)
    #expect(history.titles(now: start + 6 * day) == ["New wrap", "Old bowl"])
    #expect(history.titles(now: start + 7 * day) == ["New wrap"])
    history.record(["Newest soup"], at: start + 8 * day)
    #expect(history.entries.map(\.title) == ["Newest soup", "New wrap"])
  }

  @Test func capsTheList() {
    var history = SuggestionHistory()
    for index in 0..<40 { history.record(["Meal \(index)"], at: start + Double(index)) }
    let titles = history.titles(now: start + 100)
    #expect(titles.count == SuggestionHistory.limit)
    #expect(titles.first == "Meal 39")
  }

  @Test func requestSendsAvoidTitlesAndLocalHour() throws {
    func json(_ request: SuggestionsRequest) throws -> [String: Any] {
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        ?? [:]
    }
    let full = try json(
      SuggestionsRequest(
        remaining: .zero, mealType: .meal, maxPrepMinutes: 20, ingredientNotes: nil,
        variationNote: nil, avoidTitles: ["Chicken salad bowl"], localHour: 19))
    #expect(full["avoid_titles"] as? [String] == ["Chicken salad bowl"])
    #expect(full["local_hour"] as? Int == 19)
    let bare = try json(
      SuggestionsRequest(
        remaining: .zero, mealType: .meal, maxPrepMinutes: 20, ingredientNotes: nil,
        variationNote: nil))
    #expect(bare["avoid_titles"] == nil)
    #expect(bare["local_hour"] == nil)
  }
}
