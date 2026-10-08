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
    if scenario == "todayOver" {
      clients.day.fetchDay = { date in
        var bundle = PreviewData.day
        bundle.date = date
        bundle.goals = MacroTotals(calories: 300, protein: 20, carbs: 40, fat: 10)
        return bundle
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
}
