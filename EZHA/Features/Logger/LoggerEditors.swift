import EZHAKit
import SwiftUI

enum LoggerDestination: Hashable {
  case portion(UUID)
  case food(UUID)
  case nutrition
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
}

struct LoggerReviewItem: View {
  var model: LoggerModel
  var item: LogItem
  var index: Int
  var compact = false

  private var reviewLabel: String? {
    if item.hasUnspecifiedPreparation { return String(localized: "Preparation not specified") }
    guard model.state.reviewItemId == item.id, let review = model.state.review else { return nil }
    switch review.kind {
    case "portion": return String(localized: "Portion estimated")
    case "identity": return String(localized: "Food identity not confirmed")
    default: return String(localized: "One detail to check")
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 12 : 24) {
      HStack(alignment: .firstTextBaseline, spacing: 16) {
        Text(item.loggerDisplayName)
          .font(.title2.weight(.semibold))
          .frame(maxWidth: .infinity, alignment: .leading)
        if model.state.items.count > 1 {
          KcalText(value: LogItemMath.macros(item).calories)
            .font(.subheadline.weight(.semibold))
        }
      }
      NavigationLink(value: LoggerDestination.portion(item.id)) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 16) {
            Text("\(item.gramsText) g")
              .font(.title3.weight(.medium))
              .foregroundStyle(.primary)
              .monospacedDigit()
            Image(systemName: "pencil").foregroundStyle(Color.brandPrimary)
          }
          if !compact {
            Text("Edit portion")
              .font(.subheadline)
              .foregroundStyle(Color.ink.opacity(0.7))
          }
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Edit portion for \(item.loggerDisplayName)")
      .accessibilityValue("\(item.gramsText) grams")
      .accessibilityIdentifier("editPortion\(index)")

      VStack(spacing: 0) {
        Divider()
        NavigationLink(value: LoggerDestination.food(item.id)) {
          HStack(spacing: 12) {
            Text(reviewLabel ?? String(localized: "Adjust food"))
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity, alignment: .leading)
            if reviewLabel != nil {
              Text("Adjust")
                .foregroundStyle(Color.brandPrimary)
                .fixedSize(horizontal: true, vertical: false)
            }
            Image(systemName: "chevron.right")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          .frame(minHeight: compact ? 44 : 56)
          .padding(.vertical, compact ? 0 : 4)
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

struct LoggerNutritionDetails: View {
  @Bindable var model: LoggerModel
  var editDescription: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var labelFields = MacroFieldsModel()

  var body: some View {
    List {
      Section(model.hasAIItems ? "Estimated meal nutrition" : "Meal nutrition") {
        LabeledContent("Calories") { KcalText(value: model.totals.calories) }
        LabeledContent("Protein", value: "\(Macros.format(model.totals.protein)) g")
        LabeledContent("Carbs", value: "\(Macros.format(model.totals.carbs)) g")
        LabeledContent("Fat", value: "\(Macros.format(model.totals.fat)) g")
      }
      ForEach(model.state.items) { item in
        Section(item.loggerDisplayName) {
          NavigationLink(value: LoggerDestination.food(item.id)) {
            LabeledContent("Portion", value: "\(item.gramsText) g")
          }
          if !item.aiNotes.isEmpty {
            Text(item.aiNotes).font(.subheadline)
          }
        }
      }
      if model.showsLabelOverrides {
        Section("Label values for this portion") {
          MacroFields(model: $labelFields)
          Button("Apply label values") {
            if let values = labelFields.values { model.applyLabelOverride(values) }
          }
          .disabled(labelFields.values == nil)
        }
      }
      if !model.state.text.isEmpty || model.imageData != nil {
        Section("Meal input") {
          if !model.state.text.isEmpty { Text(model.state.text).font(.subheadline) }
          Button("Edit description") {
            editDescription()
            dismiss()
          }
        }
      }
    }
    .navigationTitle("Nutrition details")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { syncLabelFields() }
    .onChange(of: model.state.items) { _, _ in syncLabelFields() }
  }

  private func syncLabelFields() {
    if let values = model.labelDisplayMacros {
      labelFields = MacroFieldsModel(values: values.rounded)
    }
  }
}
