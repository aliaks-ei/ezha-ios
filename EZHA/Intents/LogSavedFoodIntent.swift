import AppIntents
import EZHAKit
import Foundation
import WidgetKit

/// A saved food or meal from the cached library.
struct SavedFoodEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved food"
  static let defaultQuery = SavedFoodQuery()

  var id: UUID
  var name: String
  var isMeal: Bool

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)", subtitle: isMeal ? "Saved meal" : "Saved food")
  }
}

struct SavedFoodQuery: EntityStringQuery {
  func entities(for identifiers: [UUID]) async throws -> [SavedFoodEntity] {
    await Self.all().filter { identifiers.contains($0.id) }
  }

  func entities(matching string: String) async throws -> [SavedFoodEntity] {
    let names = LibraryFilter.all.apply(to: await Self.foods(), search: string).map(\.id)
    return await Self.all().filter { names.contains($0.id) }
  }

  func suggestedEntities() async throws -> [SavedFoodEntity] {
    Array(await Self.all().prefix(10))
  }

  static func foods() async -> [SavedFood] {
    LibraryFilter.sorted(await FileCache().read("library") ?? [])
  }

  static func all() async -> [SavedFoodEntity] {
    await foods().map { SavedFoodEntity(id: $0.id, name: $0.name, isMeal: $0.isMeal) }
  }
}

/// Logs a saved food (default grams) or meal (1 portion) to today, in the background.
struct LogSavedFoodIntent: AppIntent {
  static let title: LocalizedStringResource = "Log saved food"
  static let description = IntentDescription(
    "Logs a saved food or meal to today with its default quantity.")

  @Parameter(title: "Food") var food: SavedFoodEntity

  init() {}

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let cache = FileCache()
    let foods: [SavedFood] = await cache.read("library") ?? []
    guard let saved = foods.first(where: { $0.id == food.id }) else {
      throw AIError.message("This item is no longer in your library.")
    }
    let items: [LogItem]
    if saved.isMeal {
      guard let ingredients: [SavedMealIngredient] = await cache.read("meal-\(saved.id.uuidString)")
      else {
        throw AIError.message("Open this meal in Ezha once, then try again.")
      }
      items = LogItemMath.fromSavedMeal(ingredients)
    } else {
      items = [LogItemMath.fromSavedFood(saved)]
    }
    guard LogItemMath.isQuickLogValid(items: items, quantity: 1) else {
      throw AIError.message("This item has missing nutrition.")
    }
    let today = DateKey.today()
    let payload = EntryPayload.build(
      date: today, imagePath: nil, items: items, sources: UsedSources(usedLibrary: true),
      isLabelPhoto: false, inputTextOverride: saved.name, extraUsedFoodIds: [saved.id])
    do {
      try await LoggingClient.live.logEntry(payload)
    } catch  where isNetworkError(error) {
      // Offline: queue it like the app does.
      try await OutboxProcessor(modelContainer: LocalStore.makeContainer()).enqueueLog(payload)
    }
    if var snapshot = SnapshotStore.read()?.asOf(today) {
      snapshot.totals = snapshot.totals + payload.entry.macros.rounded
      snapshot.updatedAt = .now
      SnapshotStore.write(snapshot)
      WidgetCenter.shared.reloadAllTimelines()
    }
    let kcal = payload.entry.calories.formatted(.number.precision(.fractionLength(0)))
    return .result(dialog: "Logged \(saved.name), \(kcal) kcal.")
  }
}
