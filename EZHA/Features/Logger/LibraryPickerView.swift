import EZHAKit
import SwiftUI

/// Pick saved foods and meals to add to the logger. Never replaces existing items.
/// A search with no match offers to describe the food to AI instead.
struct LibraryPickerView: View {
  var onAdd: (_ items: [LogItem], _ firstName: String?, _ mealIds: [UUID]) -> Void
  var onDescribe: (_ text: String) -> Void
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var search = ""
  @State private var isSearchPresented = false
  @State private var filter = LibraryFilter.all
  @State private var selection: [(food: SavedFood, items: [LogItem])] = []
  @State private var loadingId: UUID?
  @State private var errorMessage: String?
  @State private var isSelectionPresented = false

  private var store: LibraryStore { appModel.libraryStore }
  private var foods: [SavedFood] { filter.apply(to: store.foods, search: search) }
  private var query: String { search.trimmingCharacters(in: .whitespaces) }
  private var isSearching: Bool { !query.isEmpty }
  private var items: [LogItem] { selection.flatMap(\.items) }

  var body: some View {
    List {
      Section {
        LibraryFilterPicker(filter: $filter)
      }
      if let errorMessage {
        Section { Text(errorMessage).foregroundStyle(Color.danger) }
      }
      if isSearching {
        Section {
          ForEach(foods) { food in button(food) }
        }
        if store.hasLoaded && foods.isEmpty {
          Section {
            Button {
              if !items.isEmpty {
                onAdd(
                  items, selection.first?.food.name, selection.filter(\.food.isMeal).map(\.food.id))
              }
              onDescribe(query)
              dismiss()
            } label: {
              Label("Estimate “\(query)” with AI", systemImage: "sparkles")
            }
            .accessibilityIdentifier("describeWithAI")
          } footer: {
            Text(
              items.isEmpty
                ? "No saved item matches. AI can estimate it from the description."
                : "No saved item matches. AI will estimate this description and keep your selected foods."
            )
          }
        }
      } else {
        LibrarySections(sections: LibraryFilter.sections(foods)) { food in button(food) }
      }
    }
    .listSectionIndexVisibility(.visible)
    .overlay {
      if store.hasLoaded && store.foods.isEmpty && !isSearching {
        ContentUnavailableView(
          "No saved items", systemImage: "books.vertical",
          description: Text("Save foods and meals in the Library tab."))
      } else if !store.hasLoaded {
        ProgressView()
      }
    }
    .searchable(text: $search, isPresented: $isSearchPresented, prompt: "Search foods and meals")
    .navigationTitle("Library")
    // Keep selected-item actions in the safe area on both iPhone and iPad, above the keyboard.
    .toolbar {
      DefaultToolbarItem(kind: .search, placement: .bottomBar)
    }
    .safeAreaInset(edge: .bottom) {
      if !items.isEmpty {
        HStack(spacing: 12) {
          selectionButton
          addButton
        }
        .controlSize(.large)
        .padding()
        .background(Color.surface)
      }
    }
    .navigationDestination(isPresented: $isSelectionPresented) {
      Group {
        List {
          ForEach(selection, id: \.food.id) { selected in
            VStack(alignment: .leading, spacing: 8) {
              Text(selected.food.name).font(.headline)
              ForEach(selected.items) { item in
                LabeledContent(item.name, value: "\(item.gramsText) g")
              }
              Button("Remove", role: .destructive) {
                selection.removeAll { $0.food.id == selected.food.id }
                if selection.isEmpty { isSelectionPresented = false }
              }
              .accessibilityLabel("Remove \(selected.food.name)")
              .accessibilityIdentifier("removeSelection-\(selected.food.name)")
              .frame(minHeight: 44)
            }
          }
        }
        .navigationTitle("Selected foods")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { isSelectionPresented = false }
          }
        }
      }
    }
    .task { await store.load() }
  }

  private var selectionButton: some View {
    Button {
      isSelectionPresented = true
    } label: {
      Image(systemName: "list.bullet")
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Review selected foods")
    .accessibilityIdentifier("reviewSelection")
  }

  private var addButton: some View {
    Button {
      onAdd(items, selection.first?.food.name, selection.filter(\.food.isMeal).map(\.food.id))
      dismiss()
    } label: {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          Text("Add ^[\(items.count) item](inflect: true)")
        } else {
          Text(
            "Add ^[\(items.count) item](inflect: true) · \(LogItemMath.totals(items).calories, format: .number.precision(.fractionLength(0))) kcal"
          )
        }
      }
      .font(.headline)
      .monospacedDigit()
    }
    .buttonStyle(.glassProminent)
    .accessibilityLabel(
      "Add ^[\(items.count) item](inflect: true), \(LogItemMath.totals(items).calories, format: .number.precision(.fractionLength(0))) kcal"
    )
    .accessibilityIdentifier("addSelected")
  }

  private func button(_ food: SavedFood) -> some View {
    Button {
      Task { await toggle(food) }
    } label: {
      row(food)
    }
    .buttonStyle(.plain)
    .disabled(loadingId != nil)
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
