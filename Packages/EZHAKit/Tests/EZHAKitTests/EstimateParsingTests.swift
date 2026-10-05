import Foundation
import Testing

@testable import EZHAKit

struct EstimateParsingTests {
  func parse(_ json: String) throws(AIError) -> Estimate { try Estimate.parse(Data(json.utf8)) }

  @Test func readsTotalsAndItems() throws {
    let estimate = try parse(
      """
      {"totals":{"calories":640,"protein":40,"carbs":70,"fat":20},"confidence":0.8,
       "source":"food_photo","food_name":"Bowl","notes":"n",
       "items":[{"name":"Rice","grams":200,"calories":260,"protein":5,"carbs":56,"fat":1,"confidence":0.9}]}
      """)
    #expect(estimate.totals.calories == 640)
    #expect(estimate.foodName == "Bowl")
    #expect(estimate.items.count == 1)
  }

  @Test func acceptsTopLevelMacrosWhenTotalsAreMissing() throws {
    let estimate = try parse(
      #"{"calories":100,"protein":1,"carbs":2,"fat":3,"source":"text","notes":""}"#)
    #expect(estimate.totals == MacroTotals(calories: 100, protein: 1, carbs: 2, fat: 3))
    #expect(estimate.items.isEmpty)
  }

  @Test func failsWithoutSourceOrNotes() {
    #expect(throws: AIError.message("Analysis returned an invalid response.")) {
      try parse(#"{"totals":{"calories":1,"protein":1,"carbs":1,"fat":1},"notes":""}"#)
    }
    #expect(throws: AIError.self) {
      try parse(#"{"totals":{"calories":1,"protein":1,"carbs":1,"fat":1},"source":"text"}"#)
    }
  }

  @Test func failsOnAnErrorFieldWithHTTP200() {
    #expect(throws: AIError.message("Model response timed out.")) {
      try parse(#"{"error":"Model response timed out."}"#)
    }
  }

  @Test func parsesSuggestionsAndRejectsAnEmptyList() throws {
    let list = try MealSuggestion.parse(
      Data(
        #"{"suggestions":[{"title":"A","description":"d","calories":1,"protein":2,"carbs":3,"fat":4}]}"#
          .utf8))
    #expect(list.first?.title == "A")
    #expect(throws: AIError.message("Suggestions returned an invalid response.")) {
      try MealSuggestion.parse(Data(#"{"suggestions":[]}"#.utf8))
    }
  }
}
