import EZHAKit
import Foundation

/// Actions shared by entry rows and the entry detail sheet.
@MainActor
enum EntryActions {
  /// Hides the row at once, deletes in 5 s, and offers "Undo".
  static func delete(_ entry: DayEntry, appModel: AppModel) {
    Task {
      guard let undo = await appModel.dayStore.delete(entry) else { return }
      appModel.showToast(String(localized: "Entry deleted"), actionTitle: String(localized: "Undo"))
      {
        Task { await undo() }
      }
    }
  }

  /// Saves the entry's items as a library meal.
  static func saveAsMeal(_ entry: DayEntry, appModel: AppModel) {
    let ingredients = entry.items.map {
      SavedMealIngredient(name: $0.name, grams: $0.grams, unit: $0.unit, macros: $0.macros)
    }
    Task {
      do {
        _ = try await appModel.clients.logging.saveMeal(nil, entry.title, ingredients)
        appModel.showToast(String(localized: "Saved to Library."))
      } catch {
        appModel.showToast(
          isNetworkError(error)
            ? String(localized: "You're offline. Library changes need a connection.")
            : error.localizedDescription)
      }
    }
  }
}
