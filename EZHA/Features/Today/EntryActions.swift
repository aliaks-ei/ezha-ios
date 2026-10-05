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

  /// Copies the items to the selected date with new ids.
  static func logAgain(_ entry: DayEntry, appModel: AppModel) {
    let newId = UUID()
    var copy = entry.entry
    copy.id = newId
    copy.date = appModel.selectedDate
    copy.createdAt = .now
    let items = entry.items.map { item in
      var item = item
      item.id = UUID()
      item.entryId = newId
      item.createdAt = nil
      return item
    }
    Task {
      do {
        let result = try await appModel.dayStore.log(
          LogPayload(entry: copy, items: items, usedFoodIds: []))
        appModel.showToast(
          result == .saved
            ? String(localized: "Meal logged.")
            : String(localized: "Saved on this device. Totals update after syncing."))
      } catch {
        appModel.showToast(error.localizedDescription)
      }
    }
  }

  /// Saves the entry's items as a library meal.
  static func saveAsMeal(_ entry: DayEntry, appModel: AppModel) {
    let ingredients = entry.items.map {
      SavedMealIngredient(name: $0.name, grams: $0.grams, macros: $0.macros)
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
