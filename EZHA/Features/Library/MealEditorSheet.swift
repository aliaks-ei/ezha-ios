import EZHAKit
import SwiftUI

/// Rename a saved meal and edit its ingredients. Saves with `save_meal`.
struct MealEditorSheet: View {
  var meal: SavedFood
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var items: [LogItem] = []
  @State private var isLoading = true
  @State private var isSaving = false
  @State private var isFoodPickerPresented = false
  @State private var errorMessage: String?
  @State private var originalItems: [LogItem] = []
  @State private var isDiscardPresented = false

  private var isDirty: Bool { name != meal.name || items != originalItems }

  init(meal: SavedFood) {
    self.meal = meal
    _name = State(initialValue: meal.name)
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving && !isLoading
      && !items.isEmpty
      && items.allSatisfy {
        NumericInput.portionError($0.gramsText) == nil && !$0.isNutritionMissing
          && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Meal name", text: $name)
        }
        Section {
          ForEach($items) { $item in
            VStack(alignment: .leading, spacing: 6) {
              TextField("Ingredient", text: $item.name)
                .font(.body.weight(.medium))
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  KcalText(value: LogItemMath.macros(item).calories).font(.subheadline)
                  MacroLine(macros: LogItemMath.macros(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                GramsField(
                  text: $item.gramsText,
                  onStep: { delta in
                    item.gramsText = LogItemMath.step(item.gramsText, by: delta).text
                  },
                  onFocusLost: {},
                  accessibilityName: String(localized: "Portion of \(item.name) in grams"))
              }
              if let error = NumericInput.portionError(item.gramsText) {
                Text(error).font(.footnote).foregroundStyle(Color.danger)
              }
              if item.isNutritionMissing {
                Text("Nutrition is missing. Remove this ingredient.")
                  .font(.footnote)
                  .foregroundStyle(Color.danger)
              }
            }
          }
          .onDelete { items.remove(atOffsets: $0) }
          Button("Add from library", systemImage: "plus") { isFoodPickerPresented = true }
        } header: {
          Text("Ingredients")
        } footer: {
          let totals = LogItemMath.totals(items)
          Text(
            "Total: \(totals.calories, format: .number.precision(.fractionLength(0))) kcal · P \(totals.protein, format: .number.precision(.fractionLength(0)))g · C \(totals.carbs, format: .number.precision(.fractionLength(0)))g · F \(totals.fat, format: .number.precision(.fractionLength(0)))g"
          )
          .monospacedDigit()
        }
        if isLoading {
          Section { ProgressView() }
        }
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(Color.danger) }
        }
      }
      .navigationTitle("Edit meal")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") {
            if isDirty { isDiscardPresented = true } else { dismiss() }
          }.disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }.disabled(!canSave)
        }
      }
      .sheet(isPresented: $isFoodPickerPresented) {
        FoodPicker { food in items.append(LogItemMath.fromSavedFood(food)) }
      }
      .task { if isLoading { await load() } }
    }
    .interactiveDismissDisabled(isDirty || isSaving)
    .alert("Discard changes?", isPresented: $isDiscardPresented) {
      Button("Keep editing", role: .cancel) {}
      Button("Discard changes", role: .destructive) { dismiss() }
    }
  }

  private func load() async {
    defer { isLoading = false }
    do {
      items = LogItemMath.fromSavedMeal(try await appModel.libraryStore.ingredients(for: meal))
      originalItems = items
    } catch {
      errorMessage = OnlineError.message(for: error)
    }
  }

  private func save() async {
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    do {
      try await appModel.libraryStore.saveMeal(
        id: meal.id, name: name.trimmingCharacters(in: .whitespaces),
        ingredients: LogItemMath.mealIngredients(from: items))
      dismiss()
    } catch {
      errorMessage = OnlineError.message(for: error)
    }
  }
}

/// Picks one saved food (not a meal).
private struct FoodPicker: View {
  var onPick: (SavedFood) -> Void
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""

  var body: some View {
    NavigationStack {
      List(LibraryFilter.foods.apply(to: appModel.libraryStore.sortedFoods, search: search)) {
        food in
        Button {
          onPick(food)
          dismiss()
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(food.name)
            Text(LibraryFilter.subtitle(food)).font(.subheadline).foregroundStyle(.secondary)
          }
          .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
      }
      .searchable(text: $search, prompt: "Search foods")
      .navigationTitle("Add ingredient")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
