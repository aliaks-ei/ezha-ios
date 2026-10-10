import EZHAKit
import Foundation
import Observation

/// Saved foods and meals: cached first, then fetched. Changes are online only.
@MainActor
@Observable
final class LibraryStore {
  private(set) var foods: [SavedFood] = []
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var errorMessage: String?
  private(set) var ingredients: [UUID: [SavedMealIngredient]] = [:]

  @ObservationIgnored private let clients: AppClients
  @ObservationIgnored private let cache: FileCache
  /// Deletes waiting for their undo window to end, by food id.
  @ObservationIgnored private var pendingDeletes: [UUID: Task<Void, Never>] = [:]

  init(clients: AppClients, cache: FileCache) {
    self.clients = clients
    self.cache = cache
  }

  /// Sorted: recently used first, then by name.
  var sortedFoods: [SavedFood] { LibraryFilter.sorted(foods) }

  func load() async {
    if !hasLoaded, let cached: [SavedFood] = await cache.read("library") {
      foods = cached
      hasLoaded = true
    }
    isLoading = true
    defer { isLoading = false }
    do {
      // A food waiting to be deleted stays hidden, even though the server still has it.
      foods = try await clients.library.list().filter { pendingDeletes[$0.id] == nil }
      hasLoaded = true
      errorMessage = nil
      await cache.write(foods, for: "library")
    } catch {
      errorMessage = OnlineError.message(for: error)
    }
  }

  /// Ingredients of a meal, cached in memory and on disk for offline logging.
  func ingredients(for meal: SavedFood) async throws -> [SavedMealIngredient] {
    let key = "meal-\(meal.id.uuidString)"
    do {
      let list = try await clients.library.ingredients(meal.id)
      ingredients[meal.id] = list
      await cache.write(list, for: key)
      return list
    } catch {
      if let cached = ingredients[meal.id] { return cached }
      if let cached: [SavedMealIngredient] = await cache.read(key) {
        ingredients[meal.id] = cached
        return cached
      }
      throw error
    }
  }

  func insert(_ draft: SavedFoodDraft) async throws -> SavedFood {
    let food = try await clients.library.insertFood(draft)
    foods.append(food)
    await persist()
    return food
  }

  func update(_ id: UUID, _ draft: SavedFoodDraft) async throws {
    let food = try await clients.library.updateFood(id, draft)
    if let index = foods.firstIndex(where: { $0.id == id }) { foods[index] = food }
    await persist()
  }

  /// Hides the food at once and deletes it on the server after `delay`. Returns the undo
  /// action. If the delete fails, the food comes back and `onFailure` gets the error.
  func delete(
    _ food: SavedFood, after delay: Duration,
    onFailure: @escaping @MainActor (Error) -> Void
  ) -> @MainActor () -> Void {
    guard let index = foods.firstIndex(where: { $0.id == food.id }) else { return {} }
    foods.remove(at: index)
    pendingDeletes[food.id]?.cancel()
    pendingDeletes[food.id] = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard let self, !Task.isCancelled else { return }
      do {
        try await clients.library.deleteFood(food.id)
        pendingDeletes[food.id] = nil
        await persist()
      } catch {
        pendingDeletes[food.id] = nil
        restore(food, at: index)
        onFailure(error)
      }
    }
    return { [weak self] in
      guard let self, let task = pendingDeletes.removeValue(forKey: food.id) else { return }
      task.cancel()
      restore(food, at: index)
    }
  }

  private func restore(_ food: SavedFood, at index: Int) {
    guard !foods.contains(where: { $0.id == food.id }) else { return }
    foods.insert(food, at: min(index, foods.count))
  }

  func toggleFavorite(_ food: SavedFood) async throws {
    let value = !food.isFavorite
    if let index = foods.firstIndex(where: { $0.id == food.id }) { foods[index].isFavorite = value }
    do {
      try await clients.library.setFavorite(food.id, value)
      await persist()
    } catch {
      if let index = foods.firstIndex(where: { $0.id == food.id }) {
        foods[index].isFavorite = !value
      }
      throw error
    }
  }

  func findDuplicate(_ name: String) async throws -> SavedFood? {
    try await clients.library.findDuplicate(name)
  }

  /// Creates or updates a meal, then reloads so the list has the new row.
  @discardableResult
  func saveMeal(id: UUID?, name: String, ingredients list: [SavedMealIngredient]) async throws
    -> UUID
  {
    let mealId = try await clients.logging.saveMeal(id, name, list)
    ingredients[mealId] = nil
    await load()
    return mealId
  }

  /// Marks foods as just used, so the sections update before the next fetch.
  func markUsed(_ ids: [UUID]) {
    for id in ids {
      if let index = foods.firstIndex(where: { $0.id == id }) { foods[index].recordUse() }
    }
  }

  func clear() {
    for task in pendingDeletes.values { task.cancel() }
    pendingDeletes = [:]
    foods = []
    ingredients = [:]
    hasLoaded = false
  }

  private func persist() async {
    await cache.write(foods, for: "library")
  }
}
