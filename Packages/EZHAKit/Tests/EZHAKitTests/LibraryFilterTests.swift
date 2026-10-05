import Foundation
import Testing

@testable import EZHAKit

struct LibraryFilterTests {
  let bowl = sampleFood(name: "Chicken rice bowl", isMeal: true, isFavorite: true)
  let breast = sampleFood(name: "Chicken breast")
  let rice = sampleFood(name: "Rice", isFavorite: true)

  @Test func searchesWordsInAnyOrderCaseInsensitive() {
    let foods = [bowl, breast, rice]
    #expect(LibraryFilter.all.apply(to: foods, search: "  RICE chicken ").map(\.id) == [bowl.id])
    #expect(LibraryFilter.all.apply(to: foods, search: "chicken").count == 2)
    #expect(LibraryFilter.foods.apply(to: foods, search: "chicken").map(\.id) == [breast.id])
    #expect(LibraryFilter.meals.apply(to: foods, search: "").map(\.id) == [bowl.id])
    #expect(LibraryFilter.favorites.apply(to: foods, search: "").map(\.id) == [bowl.id, rice.id])
  }

  @Test func putsRecentlyUsedFirstThenSortsByName() {
    var used = rice
    used.lastUsedAt = Date(timeIntervalSince1970: 200)
    var older = bowl
    older.lastUsedAt = Date(timeIntervalSince1970: 100)
    let zucchini = sampleFood(name: "Zucchini")
    let apple = sampleFood(name: "apple")
    let sorted = LibraryFilter.sorted([zucchini, older, breast, used, apple])
    #expect(
      sorted.map(\.name) == ["Rice", "Chicken rice bowl", "apple", "Chicken breast", "Zucchini"])
  }

  @Test func limitsRecentsTo16() {
    let foods = (0..<20).map { i in
      sampleFood(name: "Food \(i)", lastUsedAt: Date(timeIntervalSince1970: Double(i)))
    }
    let sorted = LibraryFilter.sorted(foods)
    #expect(sorted.prefix(16).map(\.name) == (4..<20).reversed().map { "Food \($0)" })
    #expect(sorted.suffix(4).map(\.name) == ["Food 0", "Food 1", "Food 2", "Food 3"])
  }

  @Test func buildsRowSubtitles() {
    #expect(LibraryFilter.subtitle(bowl) == "Saved meal")
    #expect(LibraryFilter.subtitle(breast) == "Per 100g · 165 kcal")
    let yogurt = sampleFood(
      per100g: MacroTotals(calories: 60, protein: 10, carbs: 4, fat: 0), unitType: .perServing,
      servingSize: 150)
    #expect(LibraryFilter.subtitle(yogurt) == "150 serving · 90 kcal")
  }
}
