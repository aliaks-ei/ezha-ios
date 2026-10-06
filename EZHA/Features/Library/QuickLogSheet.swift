import EZHAKit
import SwiftUI

/// Log a saved food (grams) or meal (portions) to the selected day without AI.
struct QuickLogSheet: View {
  var food: SavedFood
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var baseItems: [LogItem] = []
  @State private var quantityText: String
  @State private var isLoading = false
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(food: SavedFood) {
    self.food = food
    _quantityText = State(
      initialValue: food.isMeal
        ? "1" : Macros.format(LogItemMath.defaultGrams(food), maxFractionDigits: 1))
  }

  private var quantity: Double? { parseNumberInput(quantityText) }
  private var items: [LogItem] {
    LogItemMath.quickLogItems(base: baseItems, isMeal: food.isMeal, quantity: quantity ?? 0)
  }
  private var isValid: Bool {
    !isSaving && !isLoading && LogItemMath.isQuickLogValid(items: items, quantity: quantity)
  }

  var body: some View {
    let totals = LogItemMath.totals(items)
    let date = appModel.selectedDate
    NavigationStack {
      Form {
        Section {
          LabeledContent(food.isMeal ? "Portions" : "Quantity") {
            GramsField(
              text: $quantityText,
              onStep: { delta in
                let next = max(0, (quantity ?? 0) + delta)
                quantityText = Macros.format(
                  min(next, food.isMeal ? 100 : LogItemMath.maxGrams), maxFractionDigits: 1)
              },
              onFocusLost: {
                if (quantity ?? 0) <= 0 {
                  quantityText =
                    food.isMeal
                    ? "1" : Macros.format(LogItemMath.defaultGrams(food), maxFractionDigits: 1)
                }
              },
              unit: food.isMeal ? "portions" : "g",
              step: food.isMeal ? 0.5 : LogItemMath.stepGrams)
          }
          VStack(alignment: .leading, spacing: 4) {
            KcalText(value: totals.calories).font(.title3.bold())
              .contentTransition(.numericText(value: totals.calories))
            MacroLine(macros: totals).font(.subheadline).foregroundStyle(.secondary)
          }
          .animation(.smooth, value: totals)
        }
        if food.isMeal && !items.isEmpty {
          Section {
            DisclosureGroup("Ingredients") {
              ForEach(items) { item in
                HStack {
                  Text(item.name)
                  Spacer()
                  Text(
                    "\(parseNumberInput(item.gramsText) ?? 0, format: .number.precision(.fractionLength(0...1))) g"
                  )
                  .foregroundStyle(.secondary)
                  .monospacedDigit()
                }
              }
            }
          }
        }
        if isLoading {
          Section { ProgressView() }
        }
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(Color.danger) }
        }
      }
      .navigationTitle(food.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") { dismiss() }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button {
          Task { await log() }
        } label: {
          Group {
            if isSaving {
              ProgressView()
            } else {
              Text(
                date == appModel.today
                  ? "Log to Today" : "Log to \(date.label(today: appModel.today))")
            }
          }
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!isValid)
        .padding()
        .accessibilityIdentifier("quickLogButton")
      }
      .task { await loadItems() }
    }
    .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
  }

  private func loadItems() async {
    guard food.isMeal else {
      baseItems = [LogItemMath.fromSavedFood(food, grams: 100)]
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      baseItems = LogItemMath.fromSavedMeal(try await appModel.libraryStore.ingredients(for: food))
      if baseItems.isEmpty || baseItems.contains(where: \.isNutritionMissing) {
        errorMessage = String(
          localized: "This item has missing nutrition. Choose another item from your library.")
      }
    } catch {
      errorMessage = OnlineError.message(for: error)
    }
  }

  private func log() async {
    isSaving = true
    defer { isSaving = false }
    let payload = EntryPayload.build(
      date: appModel.selectedDate, imagePath: nil, items: items,
      sources: UsedSources(usedLibrary: true), isLabelPhoto: false, inputTextOverride: food.name,
      extraUsedFoodIds: [food.id])
    do {
      let result = try await appModel.dayStore.log(payload)
      appModel.libraryStore.markUsed(payload.usedFoodIds)
      appModel.showToast(
        result == .saved
          ? String(localized: "Meal logged.")
          : String(localized: "Saved on this device. Totals update after syncing."))
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

#Preview {
  QuickLogSheet(food: PreviewData.foods[1])
    .environment(AppModel(clients: .preview, inMemory: true))
}
