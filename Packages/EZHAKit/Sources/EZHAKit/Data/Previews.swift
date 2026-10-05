import Foundation

/// Sample data for Xcode Previews.
public enum PreviewData {
  public static let today = DateKey.today()
  public static let basic = DailyTarget(
    id: UUID(), name: "Basic", caloriesTarget: 2100, proteinTarget: 140, carbsTarget: 220,
    fatTarget: 70)
  public static let cut = DailyTarget(
    id: UUID(), name: "Cut", caloriesTarget: 1800, proteinTarget: 160, carbsTarget: 150,
    fatTarget: 55)

  public static func entry(
    _ name: String, _ macros: MacroTotals, source: AISource = .text, minutesAgo: Double = 60
  ) -> DayEntry {
    let id = UUID()
    let item = FoodEntryItem(
      id: UUID(), entryId: id, name: name, grams: 250, macros: macros, aiConfidence: 0.8,
      aiNotes: "")
    let entry = FoodEntry(
      id: id, date: today, inputType: .text, inputText: name, imagePath: nil, macros: macros,
      aiConfidence: 0.8, aiSource: source, aiNotes: "",
      createdAt: Date.now.addingTimeInterval(-minutesAgo * 60))
    return DayEntry(entry: entry, items: [item])
  }

  public static let entries = [
    entry("Chicken rice bowl", MacroTotals(calories: 520, protein: 35, carbs: 56, fat: 14)),
    entry(
      "Greek yogurt, granola", MacroTotals(calories: 120, protein: 5, carbs: 14, fat: 6),
      source: .library, minutesAgo: 240),
  ]

  public static let day = DayBundle(
    date: today, target: basic, goals: basic.macros,
    totals: entries.reduce(.zero) { $0 + $1.entry.macros }, targets: [basic, cut],
    entries: entries)

  public static let foods = [
    SavedFood(
      id: UUID(), name: "Chicken breast",
      per100g: MacroTotals(calories: 165, protein: 31, carbs: 0, fat: 3.6), isFavorite: true),
    SavedFood(
      id: UUID(), name: "Greek yogurt", unitType: .perServing, servingSize: 150,
      servingUnit: "cup", per100g: MacroTotals(calories: 60, protein: 10, carbs: 4, fat: 0.4)),
    SavedFood(id: UUID(), name: "Overnight oats", isMeal: true),
  ]

  public static let ingredients = [
    SavedMealIngredient(
      name: "Oats", grams: 60, macros: MacroTotals(calories: 230, protein: 8, carbs: 40, fat: 4)),
    SavedMealIngredient(
      name: "Milk", grams: 200, macros: MacroTotals(calories: 100, protein: 7, carbs: 10, fat: 4)),
  ]

  public static let estimate = Estimate(
    totals: MacroTotals(calories: 640, protein: 40, carbs: 70, fat: 20), confidence: 0.8,
    source: "text", foodName: "Chicken bowl", notes: "Typical portion",
    items: [
      .init(
        name: "Chicken", grams: 150,
        macros: MacroTotals(calories: 250, protein: 35, carbs: 0, fat: 10), confidence: 0.85),
      .init(
        name: "Rice", grams: 200,
        macros: MacroTotals(calories: 390, protein: 5, carbs: 70, fat: 10), confidence: 0.8),
    ])

  public static let suggestions = [
    MealSuggestion(
      title: "Salmon and quinoa", description: "Baked salmon with quinoa and greens.",
      macros: MacroTotals(calories: 550, protein: 40, carbs: 45, fat: 20)),
    MealSuggestion(
      title: "Turkey wrap", description: "Whole wheat wrap with turkey and veg.",
      macros: MacroTotals(calories: 420, protein: 32, carbs: 40, fat: 12)),
    MealSuggestion(
      title: "Tofu stir fry", description: "Tofu, peppers, and rice noodles.",
      macros: MacroTotals(calories: 480, protein: 25, carbs: 60, fat: 15),
      notes: "Use low-sodium soy sauce."),
  ]
}

extension DayClient {
  public static let preview = DayClient(
    fetchDay: { _ in PreviewData.day },
    setTarget: { _, _, _ in },
    deleteEntry: { _ in },
    imageURL: { _ in URL(string: "https://example.com/photo.jpg")! }
  )
}

extension LoggingClient {
  public static let preview = LoggingClient(
    logEntry: { _ in },
    saveMeal: { _, _, _ in UUID() },
    uploadImage: { _, id in "preview/\(id).jpg" }
  )
}

extension LibraryClient {
  public static let preview = LibraryClient(
    list: { PreviewData.foods },
    ingredients: { _ in PreviewData.ingredients },
    insertFood: { draft in SavedFood(id: UUID(), name: draft.name, per100g: draft.per100g) },
    updateFood: { id, draft in SavedFood(id: id, name: draft.name, per100g: draft.per100g) },
    deleteFood: { _ in },
    setFavorite: { _, _ in },
    findDuplicate: { _ in nil }
  )
}

extension TargetsClient {
  public static let preview = TargetsClient(
    list: { [PreviewData.basic, PreviewData.cut] },
    save: { id, _, _, _ in id ?? UUID() },
    delete: { _, _ in }
  )
}

extension AIClient {
  public static let preview = AIClient(
    estimateStream: { _ in
      AsyncThrowingStream { continuation in
        continuation.yield(.status("requesting_model"))
        continuation.yield(.result(PreviewData.estimate))
        continuation.finish()
      }
    },
    suggestions: { _ in PreviewData.suggestions }
  )
}

extension AccountClient {
  public static let preview = AccountClient(
    userChanges: {
      AsyncStream { $0.yield(AccountUser(id: UUID(), email: "preview@example.com")) }
    },
    signInWithApple: { _, _ in },
    signInWithGoogle: {},
    signIn: { _, _ in },
    signUp: { _, _ in false },
    resetPassword: { _ in },
    updatePassword: { _ in },
    handleURL: { _ in .signedIn },
    signOut: {},
    deleteAccount: {}
  )
}
