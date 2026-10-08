import EZHAKit
import SwiftUI

/// Saved foods and meals: pinned sections, A–Z index, ranked search, quick log, edit, delete.
struct LibraryView: View {
  @Environment(AppModel.self) private var appModel
  @State private var search = ""
  @State private var filter = LibraryFilter.all
  @State private var quickLog: SavedFood?
  @State private var editing: SavedFood?
  @State private var isAddPresented = false
  @State private var pendingDelete: SavedFood?
  @State private var favoriteBounce: [UUID: Int] = [:]

  private var store: LibraryStore { appModel.libraryStore }
  private var foods: [SavedFood] { filter.apply(to: store.foods, search: search) }
  private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

  var body: some View {
    NavigationStack {
      List {
        Section {
          LibraryFilterPicker(filter: $filter)
        }
        if let error = store.errorMessage, store.hasLoaded {
          Section {
            ErrorBanner(message: error) { Task { await store.load() } }
          }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }
        if store.hasLoaded {
          if isSearching {
            Section {
              ForEach(foods) { food in row(food) }
            }
            .listRowBackground(Color.surface)
          } else {
            LibrarySections(sections: LibraryFilter.sections(foods)) { food in row(food) }
              .listRowBackground(Color.surface)
          }
        } else if store.isLoading {
          Section {
            ForEach(PreviewData.foods) { food in
              LibraryRow(food: food, onLog: {})
            }
          }
          .redacted(reason: .placeholder)
          .accessibilityLabel("Loading")
        }
      }
      .listSectionIndexVisibility(.visible)
      .scrollContentBackground(.hidden)
      .background(Color.canvas)
      .overlay { emptyState }
      .searchable(text: $search, prompt: "Search foods and meals")
      .navigationTitle("Library")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Add to Library", systemImage: "square.and.pencil") { isAddPresented = true }
            .accessibilityIdentifier("addToLibrary")
        }
      }
      .refreshable { await store.load() }
      .task { await store.load() }
      .sheet(item: $quickLog) { food in QuickLogSheet(food: food) }
      .sheet(item: $editing) { food in
        if food.isMeal { MealEditorSheet(meal: food) } else { FoodEditorSheet(food: food) }
      }
      .sheet(isPresented: $isAddPresented) { AddFoodSheet() }
      .confirmationDialog(
        "Delete \(pendingDelete?.name ?? "")?",
        isPresented: Binding(
          get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
        titleVisibility: .visible, presenting: pendingDelete
      ) { food in
        Button("Delete", role: .destructive) { Task { await delete(food) } }
      } message: { _ in
        Text("This removes it from your library. Logged meals stay.")
      }
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    if store.hasLoaded && foods.isEmpty {
      if !search.isEmpty {
        ContentUnavailableView.search(text: search)
      } else if store.foods.isEmpty {
        ContentUnavailableView {
          Label("Your library is empty", systemImage: "books.vertical")
        } description: {
          Text("Save foods and meals to log them in a tap.")
        } actions: {
          Button("Add food") { isAddPresented = true }
            .buttonStyle(.glassProminent)
        }
      } else {
        ContentUnavailableView("Nothing here yet", systemImage: "books.vertical")
      }
    } else if !store.hasLoaded, let error = store.errorMessage {
      ContentUnavailableView {
        Label("Library unavailable", systemImage: "wifi.slash")
      } description: {
        Text(error)
      } actions: {
        Button("Try again") { Task { await store.load() } }
      }
    }
  }

  private func row(_ food: SavedFood) -> some View {
    Button {
      quickLog = food
    } label: {
      LibraryRow(food: food, bounce: favoriteBounce[food.id] ?? 0) { quickLog = food }
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .leading) {
      Button(
        food.isFavorite ? "Unfavorite" : "Favorite",
        systemImage: food.isFavorite ? "star.slash" : "star"
      ) {
        Task { await toggleFavorite(food) }
      }
      .tint(.brandAccent)
    }
    .swipeActions(edge: .trailing) {
      Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = food }
    }
    .contextMenu {
      Button("Log", systemImage: "plus.circle") { quickLog = food }
      Button(
        food.isFavorite ? "Unfavorite" : "Favorite",
        systemImage: food.isFavorite ? "star.slash" : "star"
      ) {
        Task { await toggleFavorite(food) }
      }
      Button("Edit", systemImage: "pencil") { editing = food }
      Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = food }
    }
  }

  private func toggleFavorite(_ food: SavedFood) async {
    favoriteBounce[food.id, default: 0] += 1
    do {
      try await store.toggleFavorite(food)
    } catch {
      appModel.showToast(OnlineError.message(for: error))
    }
  }

  private func delete(_ food: SavedFood) async {
    do {
      try await store.delete(food)
    } catch {
      appModel.showToast(OnlineError.message(for: error))
    }
  }
}

/// All / Foods / Meals. Favorites is a section, not a filter.
struct LibraryFilterPicker: View {
  @Binding var filter: LibraryFilter

  var body: some View {
    Picker("Filter", selection: $filter) {
      Text("All").tag(LibraryFilter.all)
      Text("Foods").tag(LibraryFilter.foods)
      Text("Meals").tag(LibraryFilter.meals)
    }
    .pickerStyle(.segmented)
    .listRowBackground(Color.clear)
    .listRowInsets(EdgeInsets())
  }
}

/// Library sections for a `List`. The first pinned section is ★ in the index, letters follow.
struct LibrarySections<Row: View>: View {
  var sections: [LibrarySection]
  @ViewBuilder var row: (SavedFood) -> Row

  var body: some View {
    ForEach(sections) { section in
      Section {
        ForEach(section.foods) { food in row(food) }
      } header: {
        header(section.kind)
      }
      .sectionIndexLabel(indexLabel(section))
    }
  }

  private func header(_ kind: LibrarySection.Kind) -> Text {
    switch kind {
    case .usual(.morning): Text("Usual in the morning")
    case .usual(.midday): Text("Usual at midday")
    case .usual(.evening): Text("Usual in the evening")
    case .favorites: Text("Favorites")
    case .recent: Text("Recent")
    case .letter(let letter): Text(verbatim: letter)
    }
  }

  private func indexLabel(_ section: LibrarySection) -> String? {
    if case .letter(let letter) = section.kind { return letter }
    return section.id == sections.first?.id ? "★" : nil
  }
}

/// Name, subtitle, favorite star, and a "Log" capsule.
struct LibraryRow: View {
  var food: SavedFood
  var bounce = 0
  var onLog: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(food.name).font(.body.weight(.medium))
          if food.isFavorite {
            Image(systemName: "star.fill")
              .font(.caption)
              .foregroundStyle(Color.brandAccent)
              .symbolEffect(.bounce, value: bounce)
              .accessibilityLabel("Favorite")
          }
        }
        Text(LibraryFilter.subtitle(food))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Spacer()
      Button("Log", action: onLog)
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityLabel("Log \(food.name)")
    }
    .frame(minHeight: 44)
    .contentShape(.rect)
  }
}

#Preview {
  LibraryView()
    .environment(AppModel(clients: .preview, inMemory: true))
}
