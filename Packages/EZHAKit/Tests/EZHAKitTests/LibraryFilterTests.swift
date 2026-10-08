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
  }

  @Test func ranksNamePrefixThenWordPrefixThenSubstringThenTypo() {
    let parfait = sampleFood(name: "Yogurt parfait")
    let greek = sampleFood(name: "Greek yogurt 2%")
    let zucchini = sampleFood(name: "Zucchini")
    let foods = [zucchini, greek, parfait, breast]
    #expect(
      LibraryFilter.all.apply(to: foods, search: "yog").map(\.name) == [
        "Yogurt parfait", "Greek yogurt 2%",
      ])
    #expect(
      LibraryFilter.all.apply(to: foods, search: "chi").map(\.name) == [
        "Chicken breast", "Zucchini",
      ])
    #expect(LibraryFilter.all.apply(to: foods, search: "chiken").map(\.name) == ["Chicken breast"])
    // Short terms get no typo tolerance.
    #expect(LibraryFilter.all.apply(to: foods, search: "chk").isEmpty)
  }

  @Test func breaksRankTiesByUseThenRecency() {
    var often = sampleFood(name: "Chicken soup")
    often.usesEvening = 9
    var recent = sampleFood(name: "Chicken wrap")
    recent.lastUsedAt = .now
    let never = sampleFood(name: "Chicken pie")
    #expect(
      LibraryFilter.all.apply(to: [never, recent, often], search: "chicken").map(\.name) == [
        "Chicken soup", "Chicken wrap", "Chicken pie",
      ])
  }

  @Test func splitsTheDayIntoThreeSlots() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    func slot(_ hour: Int) -> TimeSlot {
      TimeSlot(date: Date(timeIntervalSince1970: Double(hour) * 3600), calendar: calendar)
    }
    #expect(
      [4, 5, 10, 11, 16, 17, 23].map(slot) == [
        .evening, .morning, .morning, .midday, .midday, .evening, .evening,
      ])
  }

  @Test func buildsUsualFavoritesRecentThenLetters() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 8 * 3600)  // 08:00, morning
    var oats = sampleFood(name: "Oats")
    oats.usesMorning = 5
    var toast = sampleFood(name: "Toast", isFavorite: true)
    toast.usesMorning = 3
    var steak = sampleFood(name: "Steak")
    steak.usesEvening = 9
    let eclair = sampleFood(name: "Éclair", isFavorite: true)
    let fresh = sampleFood(name: "Apple", lastUsedAt: now - 3600)
    let stale = sampleFood(name: "Bagel", lastUsedAt: now - 8 * 86_400)
    let digits = sampleFood(name: "7up")
    let sections = LibraryFilter.sections(
      [steak, digits, stale, fresh, eclair, toast, oats], now: now, calendar: calendar)
    #expect(
      sections.map(\.id) == [
        "usual", "favorites", "recent", "letter-A", "letter-B", "letter-E", "letter-O", "letter-S",
        "letter-T", "letter-#",
      ])
    #expect(sections[0].kind == .usual(.morning))
    #expect(sections[0].foods.map(\.name) == ["Oats", "Toast"])
    #expect(sections[1].foods.map(\.name) == ["Éclair"])
    #expect(sections[2].foods.map(\.name) == ["Apple"])
    // Every item stays reachable under its letter.
    #expect(sections.dropFirst(3).flatMap(\.foods).count == 7)
  }

  @Test func recordUseCountsTheSlot() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    var food = sampleFood()
    food.recordUse(at: Date(timeIntervalSince1970: 13 * 3600), calendar: calendar)
    #expect(food.usesMidday == 1)
    #expect(food.useCount == 1)
    #expect(food.lastUsedAt == Date(timeIntervalSince1970: 13 * 3600))
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
