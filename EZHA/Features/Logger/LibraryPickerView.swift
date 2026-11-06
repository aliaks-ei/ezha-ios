import EZHAKit
import SwiftUI

/// Pick saved foods and meals to add to the logger. Never replaces existing items.
/// A search with no match offers to describe the food to AI instead.
struct LibraryPickerView: View {
  var onAdd: (_ items: [LogItem], _ firstName: String?, _ mealIds: [UUID]) -> Void
  var onDescribe: (_ text: String) -> Void
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
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
    // Floating glass bar: the list scrolls under it with the system edge effect and gets a
    // bottom content inset, so the last row scrolls clear of it.
    .safeAreaBar(edge: .bottom) {
      if !selection.isEmpty {
        LibrarySelectionBar(
          count: selection.count, calories: LogItemMath.totals(items).calories,
          onReview: { isSelectionPresented = true },
          onAdd: {
            onAdd(items, selection.first?.food.name, selection.filter(\.food.isMeal).map(\.food.id))
            dismiss()
          }
        )
        // Bars stop growing at xxxLarge, like system toolbars; long press shows the large
        // content viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Same side inset as the search bar in the bottom toolbar below.
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.smooth(duration: 0.3), value: selection.isEmpty)
    .sheet(isPresented: $isSelectionPresented) {
      NavigationStack {
        List {
          ForEach(selection, id: \.food.id) { selected in
            VStack(alignment: .leading, spacing: 8) {
              Text(selected.food.name).font(.headline)
              ForEach(selected.items) { item in
                LabeledContent(item.name, value: "\(item.gramsText) \(item.unit.symbol)")
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
      .presentationDetents([.medium, .large])
    }
    .task { await store.load() }
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

/// One glass capsule: the selection summary (opens the review) and the Add action.
/// Labels stay on one line: each picks the longest version that fits.
private struct LibrarySelectionBar: View {
  var count: Int
  var calories: Double
  var onReview: () -> Void
  var onAdd: () -> Void
  /// The search bar's height, scaled with text (capped by the caller), so the bar matches it.
  @ScaledMetric(relativeTo: .body) private var height: CGFloat = 46

  private var kcal: String {
    calories.formatted(.number.precision(.fractionLength(0)))
  }

  var body: some View {
    HStack(spacing: 0) {
      Button(action: onReview) {
        HStack(spacing: 8) {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
              Text("\(count) selected").fontWeight(.semibold)
              Text("· \(kcal) kcal").foregroundStyle(.secondary)
            }
            Text("\(count) selected").fontWeight(.semibold)
            Text(count, format: .number).fontWeight(.semibold)
          }
          .lineLimit(1)
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.up")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(count) selected, \(kcal) kcal")
      .accessibilityHint("Shows selected items")
      .accessibilityShowsLargeContentViewer()
      .accessibilityIdentifier("reviewSelection")

      Button(action: onAdd) {
        Text("Add")
          .font(.headline)
          .lineLimit(1)
          .foregroundStyle(.white)
          .padding(.horizontal, 22)
          .frame(maxHeight: .infinity)
          .background(Color.accentColor, in: .capsule)
          // The tap target reaches the bar's edge; the visible capsule sits inside it.
          .padding(5)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .fixedSize(horizontal: true, vertical: false)
      .accessibilityLabel("Add ^[\(count) item](inflect: true)")
      .accessibilityShowsLargeContentViewer()
      .accessibilityIdentifier("addSelected")
    }
    .frame(height: height)
    .glassEffect(.regular.interactive(), in: .capsule)
  }
}
