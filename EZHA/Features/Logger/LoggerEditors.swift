import EZHAKit
import SwiftUI

enum LoggerDestination: Hashable {
  case portion(UUID)
  case food(UUID)
}

extension LogItem {
  /// Keep the estimator's name intact in the payload; disclose this qualifier separately in review.
  var loggerDisplayName: String {
    let qualifier = ", preparation unspecified"
    guard name.lowercased().hasSuffix(qualifier) else { return name }
    return String(name.dropLast(qualifier.count))
  }

  var hasUnspecifiedPreparation: Bool {
    name.lowercased().hasSuffix(", preparation unspecified")
  }

  /// Nutrition per 100 g, whatever basis the item is stored in.
  var per100g: MacroTotals {
    macroBasis == .per100g ? base : base.scaled(by: 100 / (baseGrams > 0 ? baseGrams : 1))
  }
}

/// One food in review: calories, macros and grams. Expanded, it shows editable per-100 g values.
struct LoggerReviewItem: View {
  var model: LoggerModel
  var item: LogItem
  var index: Int
  var isExpanded: Bool
  var onToggle: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var committedGrams: String?
  @State private var isRemovePresented = false

  private var reviewLabel: String? {
    if item.hasUnspecifiedPreparation { return String(localized: "Preparation not specified") }
    guard model.state.reviewItemId == item.id, let review = model.state.review else { return nil }
    switch review.kind {
    case "portion": return String(localized: "Portion estimated")
    case "identity": return String(localized: "Food identity not confirmed")
    default: return String(localized: "One detail to check")
    }
  }

  private var sourceLabel: String {
    switch item.origin {
    case .ai:
      model.state.aiItemsFromLabel
        ? String(localized: "From label") : String(localized: "Estimate")
    case .libraryFood: String(localized: "Saved food")
    case .libraryMeal: String(localized: "Saved meal")
    }
  }

  var body: some View {
    let macros = LogItemMath.macros(item)
    VStack(alignment: .leading, spacing: 8) {
      Button(action: onToggle) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(item.loggerDisplayName)
              .font(.headline)
              .frame(maxWidth: .infinity, alignment: .leading)
            KcalText(value: macros.calories).font(.headline)
          }
          HStack(spacing: 6) {
            MacroLine(macros: macros)
            Image(systemName: "chevron.down")
              .font(.caption.weight(.semibold))
              .rotationEffect(.degrees(isExpanded ? 180 : 0))
              .accessibilityHidden(true)
          }
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("foodRow\(index)")
      .accessibilityHint(
        isExpanded ? "Hides nutrition per 100 grams" : "Shows nutrition per 100 grams")

      let stacked = dynamicTypeSize.isAccessibilitySize
      (stacked ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())) {
        Text("Portion")
        if !stacked { Spacer() }
        GramsField(
          text: Binding(get: { item.gramsText }, set: { model.setGrams(item.id, $0) }),
          onStep: step, onFocusLost: commitGrams)
      }

      if let reviewLabel {
        NavigationLink(value: LoggerDestination.food(item.id)) {
          HStack(spacing: 12) {
            Text(reviewLabel)
              .font(.subheadline)
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity, alignment: .leading)
            Text("Adjust")
              .font(.subheadline)
              .foregroundStyle(Color.brandPrimary)
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          .frame(minHeight: 44)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("adjustFood\(index)")
      }

      if item.isNutritionMissing {
        Text("Nutrition is missing. Remove this food to log the rest of your meal.")
          .font(.subheadline)
          .foregroundStyle(Color.danger)
      }

      if isExpanded {
        if !item.isNutritionMissing {
          if stacked {
            stackedNutrition(macros)
          } else {
            nutritionTable(macros).padding(.top, 4)
          }
        }
        HStack {
          if item.origin == .ai && reviewLabel == nil {
            NavigationLink("Adjust estimate", value: LoggerDestination.food(item.id))
              .accessibilityIdentifier("adjustFood\(index)")
          }
          Spacer()
          Button("Remove", role: .destructive) { isRemovePresented = true }
            .accessibilityIdentifier("removeFood\(index)")
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
      }
    }
    .onAppear { committedGrams = item.gramsText }
    .confirmationDialog(
      "Remove this food?", isPresented: $isRemovePresented, titleVisibility: .visible
    ) {
      Button("Remove food", role: .destructive) { model.removeItem(item.id) }
    }
  }

  private func nutritionTable(_ macros: MacroTotals) -> some View {
    let per100g = item.per100g
    return Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 8) {
      GridRow {
        Text(sourceLabel)
          .frame(maxWidth: .infinity, alignment: .leading)
          .gridColumnAlignment(.leading)
        Text("Per 100 g")
        Text("\(item.gramsText) g")
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
      row("Calories", "calories", \.calories, per100g, portion: KcalText(value: macros.calories))
      row("Protein", "protein", \.protein, per100g, portion: GramsText(value: macros.protein))
      row("Carbs", "carbs", \.carbs, per100g, portion: GramsText(value: macros.carbs))
      row("Fat", "fat", \.fat, per100g, portion: GramsText(value: macros.fat))
    }
  }

  /// Accessibility text sizes: one macro per block, the per-100 g field above the portion value.
  private func stackedNutrition(_ macros: MacroTotals) -> some View {
    let per100g = item.per100g
    let rows: [(LocalizedStringKey, String, WritableKeyPath<MacroTotals, Double>, String)] = [
      ("Calories", "calories", \.calories, "\(Macros.format(macros.calories, maxFractionDigits: 0)) kcal"),
      ("Protein", "protein", \.protein, "\(Macros.format(macros.protein, maxFractionDigits: 1)) g"),
      ("Carbs", "carbs", \.carbs, "\(Macros.format(macros.carbs, maxFractionDigits: 1)) g"),
      ("Fat", "fat", \.fat, "\(Macros.format(macros.fat, maxFractionDigits: 1)) g"),
    ]
    return VStack(alignment: .leading, spacing: 12) {
      Text(sourceLabel).font(.footnote).foregroundStyle(.secondary)
      ForEach(rows, id: \.1) { title, id, keyPath, portion in
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
          HStack {
            Per100gField(title: title, value: per100g[keyPath: keyPath]) {
              model.setPer100g(item.id, keyPath, $0)
            }
            .accessibilityIdentifier("per100g-\(id)\(index)")
            Text("per 100 g").foregroundStyle(.secondary)
          }
          Text("\(portion) in \(item.gramsText) g")
            .fontWeight(.semibold)
            .fontDesign(.rounded)
            .monospacedDigit()
        }
      }
    }
  }

  private func row(
    _ title: LocalizedStringKey, _ id: String, _ keyPath: WritableKeyPath<MacroTotals, Double>,
    _ per100g: MacroTotals, portion: some View
  ) -> some View {
    GridRow {
      Text(title).gridColumnAlignment(.leading)
      Per100gField(title: title, value: per100g[keyPath: keyPath]) {
        model.setPer100g(item.id, keyPath, $0)
      }
      .accessibilityIdentifier("per100g-\(id)\(index)")
      portion.fontWeight(.semibold)
    }
  }

  private func step(_ delta: Double) {
    model.step(item.id, by: delta)
    if model.state.reviewItemId == item.id && model.state.review?.kind == "portion" {
      model.confirmReviewPortion()
    }
  }

  /// A typed weight confirms a portion question and is kept as context for later estimates.
  private func commitGrams() {
    model.gramsFocusLost(item.id)
    guard let grams = model.state.items.first(where: { $0.id == item.id })?.gramsText,
      grams != committedGrams
    else { return }
    if model.updatePortion(item.id, grams: grams) { committedGrams = grams }
  }
}

/// "46.5 g"
private struct GramsText: View {
  var value: Double

  var body: some View {
    Text("\(Macros.format(value, maxFractionDigits: 1)) g")
      .fontDesign(.rounded)
      .monospacedDigit()
  }
}

/// A per-100 g value. Only typing changes the item, so showing the field never rewrites it.
private struct Per100gField: View {
  var title: LocalizedStringKey
  var value: Double
  var onChange: (Double) -> Void
  @State private var text = ""
  @FocusState private var isFocused: Bool
  @ScaledMetric private var width: CGFloat = 56

  var body: some View {
    TextField(title, text: $text, prompt: Text(verbatim: "0"))
      .keyboardType(.decimalPad)
      .multilineTextAlignment(.trailing)
      .fontDesign(.rounded)
      .monospacedDigit()
      .focused($isFocused)
      .frame(width: width)
      .padding(.vertical, 6)
      .padding(.horizontal, 8)
      .background(Color.canvas, in: .rect(cornerRadius: 8))
      // The whole tinted box focuses the field, not only the text.
      .contentShape(.rect)
      .onTapGesture { isFocused = true }
      .onAppear { text = Macros.format(value, maxFractionDigits: 1) }
      .onChange(of: value) { _, value in
        if !isFocused { text = Macros.format(value, maxFractionDigits: 1) }
      }
      .onChange(of: text) { _, text in
        guard isFocused, let parsed = parseNumberInput(text) else { return }
        onChange(parsed)
      }
      .onChange(of: isFocused) { _, focused in
        if !focused { text = Macros.format(value, maxFractionDigits: 1) }
      }
  }
}

/// Portion changes stay local until Done, so Back never leaves a half-edited quantity.
struct LoggerPortionEditor: View {
  var model: LoggerModel
  var itemId: UUID
  @Environment(\.dismiss) private var dismiss
  @State private var grams: String

  init(model: LoggerModel, itemId: UUID) {
    self.model = model
    self.itemId = itemId
    _grams = State(initialValue: model.state.items.first { $0.id == itemId }?.gramsText ?? "100")
  }

  private var item: LogItem? { model.state.items.first { $0.id == itemId } }
  private var isValid: Bool {
    guard let value = parseNumberInput(grams) else { return false }
    return value.isFinite && value > 0 && value <= LogItemMath.maxGrams
  }

  var body: some View {
    Form {
      if let item {
        Section {
          Text(item.loggerDisplayName).font(.headline)
          LabeledContent("Grams eaten") {
            GramsField(
              text: $grams,
              onStep: { grams = LogItemMath.step(grams, by: $0).text },
              onFocusLost: {})
          }
          .accessibilityIdentifier("portionField")
        } footer: {
          if !isValid {
            Text("Enter a weight greater than 0 and no more than 5,000 g.")
          } else if model.state.reviewItemId == itemId && model.state.review?.kind == "portion" {
            Text("This confirms the estimated portion. Nutrition updates without another estimate.")
          }
        }
        Section {
          let edited = editedItem(item)
          LabeledContent(model.hasAIItems ? "Estimated calories" : "Calories") {
            if isValid {
              KcalText(value: LogItemMath.macros(edited).calories)
            } else {
              Text("—")
            }
          }
        }
      }
    }
    .navigationTitle("Edit portion")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") {
          if model.updatePortion(itemId, grams: grams) { dismiss() }
        }
        .disabled(!isValid || item == nil)
        .accessibilityIdentifier("confirmPortion")
      }
    }
  }

  private func editedItem(_ item: LogItem) -> LogItem {
    var edited = item
    edited.gramsText = grams
    return edited
  }
}

struct LoggerFoodEditor: View {
  @Bindable var model: LoggerModel
  var itemId: UUID
  var runAI: (@escaping () -> Void) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var detail = ""
  @State private var isRemovePresented = false

  private var item: LogItem? { model.state.items.first { $0.id == itemId } }
  private var review: Estimate.Review? {
    model.state.reviewItemId == itemId ? model.state.review : nil
  }
  private var answer: Binding<String> {
    Binding(
      get: { review == nil ? detail : model.state.reviewAnswer ?? "" },
      set: {
        if review == nil { detail = $0 } else { model.state.reviewAnswer = $0 }
      })
  }

  var body: some View {
    Form {
      if let item {
        Section {
          Text(item.loggerDisplayName).font(.headline)
          NavigationLink(value: LoggerDestination.portion(itemId)) {
            LabeledContent("Portion", value: "\(item.gramsText) g")
          }
        }
        if item.origin == .ai {
          Section {
            Text(review?.question ?? String(localized: "What needs to change about this food?"))
            if let review, review.kind == "portion" {
              NavigationLink("Confirm portion", value: LoggerDestination.portion(itemId))
            } else {
              if let question = review?.question.lowercased(),
                question.contains("raw") && question.contains("cooked")
              {
                HStack(spacing: 12) {
                  preparationButton("Raw", answer: "The \(item.gramsText) g was weighed raw.")
                  preparationButton("Cooked", answer: "The \(item.gramsText) g was weighed cooked.")
                }
                .buttonStyle(.bordered)
              }
              TextField("Add a detail, including any added fat", text: answer, axis: .vertical)
                .lineLimit(2...6)
                .accessibilityIdentifier("reviewAnswer")
            }
          } footer: {
            Text("Optional. You can return and log the current estimate without answering.")
          }
        }
        if !item.aiNotes.isEmpty {
          Section("Estimate details") {
            Text(item.aiNotes).font(.subheadline)
          }
        }
        Section {
          Button("Remove food", role: .destructive) { isRemovePresented = true }
            .accessibilityIdentifier("removeFood")
        }
      }
    }
    .navigationTitle("Adjust food")
    .navigationBarTitleDisplayMode(.inline)
    .safeAreaInset(edge: .bottom) {
      if item?.origin == .ai && review?.kind != "portion" {
        Button {
          let text = answer.wrappedValue
          runAI {
            if review != nil {
              model.answerReview()
            } else {
              model.refineItem(itemId, detail: text)
            }
            if model.isEstimating { dismiss() }
          }
        } label: {
          Text("Update estimate")
            .font(.headline)
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(
          answer.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || model.isEstimating || model.isSaving
        )
        .padding()
        .background(Color.surface)
        .accessibilityIdentifier("updateEstimate")
      }
    }
    .confirmationDialog(
      "Remove this food?", isPresented: $isRemovePresented, titleVisibility: .visible
    ) {
      Button("Remove food", role: .destructive) {
        model.removeItem(itemId)
        dismiss()
      }
    }
  }

  private func preparationButton(_ title: LocalizedStringKey, answer text: String) -> some View {
    Button {
      answer.wrappedValue = text
    } label: {
      Text(title).frame(maxWidth: .infinity, minHeight: 44)
    }
  }
}
