import EZHAKit
import SwiftUI

/// Pick saved foods and meals to add to the logger. Never replaces existing items.
struct LibraryPickerView: View {
  var onAdd: (_ items: [LogItem], _ firstName: String?, _ mealIds: [UUID]) -> Void
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var filter = LibraryFilter.all
  @State private var selection: [(food: SavedFood, items: [LogItem])] = []
  @State private var loadingId: UUID?
  @State private var errorMessage: String?

  private var store: LibraryStore { appModel.libraryStore }
  private var foods: [SavedFood] { filter.apply(to: store.sortedFoods, search: search) }
  private var items: [LogItem] { selection.flatMap(\.items) }

  var body: some View {
    List {
      Section {
        Picker("Filter", selection: $filter) {
          Text("All").tag(LibraryFilter.all)
          Text("Foods").tag(LibraryFilter.foods)
          Text("Meals").tag(LibraryFilter.meals)
          Text("Favorites").tag(LibraryFilter.favorites)
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
      }
      if let errorMessage {
        Section { Text(errorMessage).foregroundStyle(Color.danger) }
      }
      Section {
        ForEach(foods) { food in
          Button {
            Task { await toggle(food) }
          } label: {
            row(food)
          }
          .buttonStyle(.plain)
          .disabled(loadingId != nil)
        }
      }
    }
    .overlay {
      if store.hasLoaded && foods.isEmpty {
        if search.isEmpty {
          ContentUnavailableView(
            "No saved items", systemImage: "books.vertical",
            description: Text("Save foods and meals in the Library tab."))
        } else {
          ContentUnavailableView.search(text: search)
        }
      } else if !store.hasLoaded {
        ProgressView()
      }
    }
    .searchable(text: $search, prompt: "Search foods and meals")
    .navigationTitle("Library")
    .safeAreaInset(edge: .bottom) {
      if !items.isEmpty {
        Button {
          onAdd(items, selection.first?.food.name, selection.filter(\.food.isMeal).map(\.food.id))
          dismiss()
        } label: {
          Text(
            "Add \(items.count) items · \(LogItemMath.totals(items).calories, format: .number.precision(.fractionLength(0))) kcal"
          )
          .font(.headline)
          .monospacedDigit()
          .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .padding()
      }
    }
    .task { await store.load() }
  }

  private func row(_ food: SavedFood) -> some View {
    let isSelected = selection.contains { $0.food.id == food.id }
    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(food.name)
          if food.isFavorite {
            Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.brandAccent)
              .accessibilityLabel("Favorite")
          }
        }
        Text(LibraryFilter.subtitle(food))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Spacer()
      if loadingId == food.id {
        ProgressView()
      } else {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isSelected ? Color.brandPrimary : Color.secondary)
          .accessibilityHidden(true)
      }
    }
    .frame(minHeight: 44)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func toggle(_ food: SavedFood) async {
    errorMessage = nil
    if let index = selection.firstIndex(where: { $0.food.id == food.id }) {
      selection.remove(at: index)
      return
    }
    guard food.isMeal else {
      selection.append((food, [LogItemMath.fromSavedFood(food)]))
      return
    }
    loadingId = food.id
    defer { loadingId = nil }
    do {
      let mealItems = LogItemMath.fromSavedMeal(try await store.ingredients(for: food))
      guard !mealItems.isEmpty, !mealItems.contains(where: \.isNutritionMissing) else {
        errorMessage = String(localized: "\(food.name) has missing nutrition. Choose another item.")
        return
      }
      selection.append((food, mealItems))
    } catch {
      errorMessage = OnlineError.message(for: error)
    }
  }
}
