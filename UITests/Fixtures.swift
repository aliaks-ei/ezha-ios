import EZHAKit
import Foundation

enum LoggerFixtures {
  static let date = DateKey("2026-10-07")!

  static let photo = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4l8AAAAASUVORK5CYII="
  )!

  static func state(_ scenario: String = "review") -> LoggerState {
    var state = LoggerState()
    guard scenario != "entry", scenario != "slowEstimate" else { return state }
    if scenario == "drink" {
      // "330 ml beer": one millilitre item, nutrition per 100 ml.
      state.text = "330 ml beer"
      state.estimateUsedText = true
      state.items = [
        LogItem(
          name: "Beer", gramsText: "330", unit: .ml, macroBasis: .per100g, baseGrams: 100,
          base: drinkPer100ml, origin: .ai)
      ]
      state.lastAnalyzed = AnalyzeGate.Fingerprint(text: state.text, photoId: nil, isLabel: false)
      return state
    }
    if scenario == "library" {
      state.items = [
        LogItem(
          name: "Greek yogurt", gramsText: "150", macroBasis: .per100g,
          baseGrams: 100, base: MacroTotals(calories: 60, protein: 10, carbs: 4, fat: 0),
          origin: .libraryFood)
      ]
      return state
    }
    state.text = "Chicken breast 100 g"
    state.estimateUsedText = true
    state.items = LogItemMath.fromEstimate(estimate())
    state.review = Estimate.Review(
      question: "Was the 100 g measured raw or cooked, and was any added fat used?",
      kind: "ingredient", itemIndex: 0)
    state.reviewItemId = state.items[0].id
    state.lastAnalyzed = AnalyzeGate.Fingerprint(text: state.text, photoId: nil, isLabel: false)
    if scenario == "multiple" {
      state.items += [
        LogItem(
          name: "Cooked rice", gramsText: "180", macroBasis: .per100g,
          baseGrams: 100, base: MacroTotals(calories: 130, protein: 2.5, carbs: 28.3, fat: 0.3),
          origin: .ai),
        LogItem(
          name: "Saved yogurt", gramsText: "100", macroBasis: .per100g,
          baseGrams: 100, base: MacroTotals(calories: 60, protein: 10, carbs: 4, fat: 0),
          origin: .libraryFood),
      ]
    }
    if scenario == "reviewFiber" {
      // PET-115: the estimate has no fiber for the chicken; the rice has fiber per 100 g.
      state.items += [
        LogItem(
          name: "Cooked rice", gramsText: "180", macroBasis: .per100g, baseGrams: 100,
          base: MacroTotals(calories: 130, protein: 2.7, carbs: 28.2, fat: 0.3, fiber: 0.4),
          origin: .ai)
      ]
    }
    if scenario == "longName" {
      // PET-112: a long name wraps next to the portion control on the compact row.
      state.items += [
        LogItem(
          name: "Grilled chicken breast with lemon, garlic and fresh herbs", gramsText: "150",
          macroBasis: .per100g, baseGrams: 100,
          base: MacroTotals(calories: 165, protein: 31, carbs: 0, fat: 3.6), origin: .ai),
        LogItem(
          name: "Saved yogurt", gramsText: "100", macroBasis: .per100g,
          baseGrams: 100, base: MacroTotals(calories: 60, protein: 10, carbs: 4, fat: 0),
          origin: .libraryFood),
      ]
    }
    if scenario == "label" {
      state.aiItemsFromLabel = true
      state.items[0].macroBasis = .per100g
      state.items[0].baseGrams = 100
      state.items[0].base = MacroTotals(calories: 442, protein: 12, carbs: 56, fat: 19)
      state.items[0].gramsText = "50"
      state.items[0].name = "Nutrition label"
      state.review = nil
      state.reviewItemId = nil
    }
    if scenario == "photoDraft" {
      state.photoId = UUID().uuidString
    }
    return state
  }

  static let drinkPer100ml = MacroTotals(calories: 43, protein: 0.5, carbs: 3.6, fat: 0)

  /// A per-serving drink: 250 ml glass, values per 100 ml.
  static let drinkFood = SavedFood(
    id: UUID(), name: "Oat drink", unitType: .perServing, servingSize: 250,
    servingUnit: "glass", amountUnit: .ml,
    per100g: MacroTotals(calories: 46, protein: 1, carbs: 6.7, fat: 1.5))

  static func estimate() -> Estimate {
    Estimate(
      totals: MacroTotals(calories: 165, protein: 31, carbs: 0, fat: 4), source: "text",
      items: [
        .init(
          name: "Chicken breast, preparation unspecified", grams: 100,
          macros: MacroTotals(calories: 165, protein: 31, carbs: 0, fat: 4),
          notes:
            "Preparation is unspecified. Confirm whether the weight was measured raw or cooked and whether any fat was added."
        )
      ], nutritionBasis: .perPortion)
  }

  /// "Greek yogurt", "Flat white", and "Banana" are usual at the current time of day,
  /// "Chicken breast" is a favorite, "Apple" and "Sourdough toast" are recent.
  static func libraryFoods() -> [SavedFood] {
    func food(
      _ name: String, kcal: Double = 100, favorite: Bool = false, daysAgo: Double? = nil,
      usual: Int = 0
    ) -> SavedFood {
      var food = SavedFood(
        id: UUID(), name: name, per100g: MacroTotals(calories: kcal, protein: 8, carbs: 12, fat: 3),
        isFavorite: favorite)
      for _ in 0..<usual { food.recordUse(at: .now) }
      food.lastUsedAt = daysAgo.map { Date.now - $0 * 86_400 }
      return food
    }
    var yogurt = PreviewData.foods[1]
    for _ in 0..<6 { yogurt.recordUse(at: .now) }
    yogurt.lastUsedAt = .now - 3600
    return [
      PreviewData.foods[0], yogurt, PreviewData.foods[2],
      food("Flat white", kcal: 45, daysAgo: 0.2, usual: 5),
      food("Banana", kcal: 89, daysAgo: 1, usual: 3),
      food("Apple", kcal: 52, daysAgo: 1),
      food("Sourdough toast", kcal: 260, daysAgo: 2),
      food("Almonds", kcal: 579), food("Avocado", kcal: 160), food("Bagel", kcal: 250),
      food("Broccoli", kcal: 34), food("Cottage cheese", kcal: 98),
      food("Dark chocolate", kcal: 600),
      food("Eggs", kcal: 143), food("Falafel", kcal: 333), food("Granola", kcal: 471),
      food("Hummus", kcal: 166), food("Kefir", kcal: 52), food("Lentil soup", kcal: 70),
      food("Mozzarella", kcal: 280), food("Olive oil", kcal: 884), food("Pasta", kcal: 158),
      food("Quinoa", kcal: 120), food("Rice cakes", kcal: 387), food("Salmon", kcal: 208),
      food("Tofu", kcal: 76), food("Tuna", kcal: 116), food("Yogurt parfait", kcal: 150),
      food("Zucchini", kcal: 17), food("7up", kcal: 39),
    ]
  }

  @MainActor
  static func app(_ scenario: String = "review") -> AppModel {
    var clients = AppClients.preview
    clients.ai = AIClient(
      estimateStream: { _ in
        AsyncThrowingStream { continuation in
          if scenario == "slowEstimate" {
            let task = Task {
              continuation.yield(.status("checking_details"))
              try? await Task.sleep(for: .seconds(3))
              continuation.yield(.result(estimate()))
              continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
          } else if scenario == "failure" {
            continuation.finish(
              throwing: AIError.message("Could not update the estimate. Try again."))
          } else {
            continuation.yield(.result(estimate()))
            continuation.finish()
          }
        }
      },
      suggestions: { _ in
        if scenario == "suggestionsFailure" {
          throw AIError.message("Could not get suggestions. Try again.")
        }
        if scenario == "suggestionsResults" { return PreviewData.suggestions }
        if scenario == "suggestionsLoading" { try await Task.sleep(for: .seconds(3)) }
        return []
      })
    if scenario == "slowLog" {
      // Offline: the log stays in the outbox, so the day shows it as a pending entry.
      clients.logging.logEntry = { _ in throw URLError(.notConnectedToInternet) }
    }
    if scenario == "todayOver" {
      clients.day.fetchDay = { date in
        var bundle = PreviewData.day
        bundle.date = date
        bundle.goals = MacroTotals(calories: 300, protein: 20, carbs: 40, fat: 10)
        return bundle
      }
    }
    if scenario == "todayFiber" || scenario == "todayFiberPartial" {
      let entries = fiberEntries(partial: scenario == "todayFiberPartial")
      clients.day.fetchDay = { date in
        var bundle = PreviewData.day
        bundle.date = date
        bundle.entries = entries
        bundle.totals = entries.reduce(.zero) { $0 + $1.entry.macros }
        return bundle
      }
    }
    if scenario == "todayEmpty" || scenario == "todayMany" {
      // No meals, or nine meals with the newest one still in the outbox.
      let entries = scenario == "todayMany" ? manyEntries() : []
      clients.day.fetchDay = { date in
        var bundle = PreviewData.day
        bundle.date = date
        bundle.entries = entries
        bundle.totals = entries.reduce(.zero) { $0 + $1.entry.macros }
        return bundle
      }
    }
    if scenario == "reviewOver" || scenario == "reviewNoTarget" {
      // The review meal (165 kcal, 31 g protein) takes the day over the calorie and protein
      // targets; or the day has no target.
      let goals =
        scenario == "reviewOver"
        ? MacroTotals(calories: 700, protein: 60, carbs: 120, fat: 30) : .zero
      clients.day.fetchDay = { date in
        var bundle = PreviewData.day
        bundle.date = date
        bundle.goals = goals
        return bundle
      }
    }
    if scenario.hasPrefix("todayWater") || scenario.hasPrefix("water") {
      // PET-116: water under, at, and over the 2,000 ml target, or with no target. Saves and
      // deletes change the fixture day, like the server; offline, they stay in the outbox.
      let water = FixtureWater(waterEntries(scenario))
      let target: Double? = scenario == "todayWaterNone" ? nil : 2000
      clients.day.fetchDay = { date in
        var bundle = PreviewData.day
        bundle.date = date
        bundle.waterTargetMl = target
        bundle.water = water.all()
        return bundle
      }
      if scenario == "todayWaterOffline" {
        clients.day.saveWater = { _ in throw URLError(.notConnectedToInternet) }
      } else {
        clients.day.saveWater = { water.save($0) }
        clients.day.deleteWater = { water.delete($0) }
      }
    }
    clients.library.list = { libraryFoods() }
    clients.library.ingredients = { _ in
      (1...12).map {
        SavedMealIngredient(
          name: "Ingredient \($0)", grams: 50,
          macros: MacroTotals(calories: 100, protein: 5, carbs: 10, fat: 3))
      }
    }
    let app = AppModel(clients: clients, inMemory: true)
    app.aiConsent = .allowed
    return app
  }

  /// Water for the scenario, newest first: 1,250 ml (under), 2,000 ml (at), 2,400 ml (over).
  static func waterEntries(_ scenario: String) -> [WaterEntry] {
    let amounts: [Double] =
      switch scenario {
      case "todayWaterAt": [500, 750, 500, 250]
      case "todayWaterOver": [650, 750, 500, 500]
      default: [170, 330, 500, 250]
      }
    let today = DateKey.today()
    return amounts.enumerated().map { index, ml in
      WaterEntry(
        date: today, amountMl: ml, createdAt: .now - Double(index + 1) * 5400,
        isPending: scenario == "waterEntries" && index == 0)
    }
  }

  /// A target with a 2,000 ml water target, for the target editor.
  static let waterTarget = DailyTarget(
    id: UUID(), name: "Basic", caloriesTarget: 2100, proteinTarget: 140, carbsTarget: 220,
    fatTarget: 70, waterTargetMl: 2000)

  /// PET-115: three meals with 18 g fiber. `partial`: the bowl has no fiber data (14 g known).
  static func fiberEntries(partial: Bool) -> [DayEntry] {
    [
      PreviewData.entry(
        "Hummus and carrots",
        MacroTotals(calories: 210, protein: 10, carbs: 18, fat: 14, fiber: 5), minutesAgo: 60),
      PreviewData.entry(
        "Chicken and rice bowl",
        MacroTotals(calories: 610, protein: 48, carbs: 62, fat: 18, fiber: partial ? nil : 4),
        minutesAgo: 240),
      PreviewData.entry(
        "Oatmeal with berries",
        MacroTotals(calories: 420, protein: 14, carbs: 68, fat: 9, fiber: 9), minutesAgo: 480),
    ]
  }

  /// PET-115: a bowl with fiber for two items and none for the sauce.
  static func fiberBowl() -> DayEntry {
    let id = UUID()
    let items = [
      (
        "Chicken breast", 150.0, MacroTotals(calories: 248, protein: 46, carbs: 0, fat: 5, fiber: 0)
      ),
      ("Cooked rice", 180, MacroTotals(calories: 234, protein: 5, carbs: 50, fat: 1, fiber: 0.7)),
      ("Teriyaki sauce", 30, MacroTotals(calories: 128, protein: 1, carbs: 12, fat: 12)),
    ].map { name, grams, macros in
      FoodEntryItem(
        id: UUID(), entryId: id, name: name, grams: grams, macros: macros, aiConfidence: 0.8,
        aiNotes: "")
    }
    let entry = FoodEntry(
      id: id, date: PreviewData.today, inputType: .text, inputText: "Chicken and rice bowl",
      imagePath: nil, macros: items.reduce(.zero) { $0 + $1.macros }, aiConfidence: 0.8,
      aiSource: .text, aiNotes: "", createdAt: .now)
    return DayEntry(entry: entry, items: items)
  }

  /// Nine meals for the Today list, newest first; the newest waits to sync.
  static func manyEntries() -> [DayEntry] {
    let meals: [(String, MacroTotals, Double)] = [
      ("Pasta salad", MacroTotals(calories: 430, protein: 14, carbs: 62, fat: 14), 20),
      ("Dark chocolate", MacroTotals(calories: 170, protein: 2, carbs: 13, fat: 12), 55),
      (
        "Salmon, roasted potatoes and green beans",
        MacroTotals(calories: 610, protein: 38, carbs: 45, fat: 28), 140
      ),
      ("Protein shake", MacroTotals(calories: 180, protein: 30, carbs: 8, fat: 3), 295),
      ("Apple", MacroTotals(calories: 95, protein: 0, carbs: 25, fat: 0), 370),
      ("Chicken rice bowl", MacroTotals(calories: 520, protein: 35, carbs: 56, fat: 14), 470),
      ("Greek yogurt, granola", MacroTotals(calories: 120, protein: 5, carbs: 14, fat: 6), 650),
      ("Coffee with milk", MacroTotals(calories: 45, protein: 2, carbs: 4, fat: 2), 805),
      ("Oatmeal with berries", MacroTotals(calories: 310, protein: 10, carbs: 54, fat: 6), 840),
    ]
    return meals.enumerated().map { index, meal in
      var entry = PreviewData.entry(meal.0, meal.1, minutesAgo: meal.2)
      entry.isPending = index == 0
      return entry
    }
  }
}

/// The fixture server's water entries.
final class FixtureWater: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [WaterEntry]

  init(_ entries: [WaterEntry]) { self.entries = entries }

  func all() -> [WaterEntry] {
    lock.withLock {
      entries.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
  }

  func save(_ entry: WaterEntry) {
    lock.withLock {
      entries.removeAll { $0.id == entry.id }
      entries.append(entry)
    }
  }

  func delete(_ id: UUID) {
    lock.withLock { entries.removeAll { $0.id == id } }
  }
}
