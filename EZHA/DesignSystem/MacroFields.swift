import EZHAKit
import SwiftUI

/// Text state for four macro fields (calories, protein, carbs, fat) and optional fiber.
struct MacroFieldsModel: Equatable {
  var calories: String
  var protein: String
  var carbs: String
  var fat: String
  /// Empty is unknown, not 0. Shown only where `MacroFields.showsFiber` is set.
  var fiber: String

  init(values: MacroTotals) {
    calories = Macros.format(values.calories, maxFractionDigits: 1)
    protein = Macros.format(values.protein, maxFractionDigits: 1)
    carbs = Macros.format(values.carbs, maxFractionDigits: 1)
    fat = Macros.format(values.fat, maxFractionDigits: 1)
    fiber = values.fiber.map { Macros.format($0, maxFractionDigits: 1) } ?? ""
  }

  init(empty: Void = ()) {
    calories = ""
    protein = ""
    carbs = ""
    fat = ""
    fiber = ""
  }

  var fiberInput: FiberInput { .text(fiber) }

  /// The parsed values, or nil when any field is not a number ≥ 0 or fiber is invalid.
  var values: MacroTotals? {
    let parsed = [calories, protein, carbs, fat].map(parseNumberInput)
    guard [calories, protein, carbs, fat].allSatisfy({ NumericInput.nutritionError($0) == nil }),
      case .value(let fiber) = fiberInput.resolved
    else { return nil }
    return MacroTotals(
      calories: parsed[0] ?? 0, protein: parsed[1] ?? 0, carbs: parsed[2] ?? 0, fat: parsed[3] ?? 0,
      fiber: fiber)
  }

  /// Each field parsed on its own, nil where it is not a number.
  var optionalValues: [Double?] { [calories, protein, carbs, fat].map(parseNumberInput) }

  /// 4/4/9 calories from the macro fields.
  var macroCalories: Double {
    Macros.caloriesFromMacros(
      protein: parseNumberInput(protein) ?? 0, carbs: parseNumberInput(carbs) ?? 0,
      fat: parseNumberInput(fat) ?? 0)
  }
}

/// Four labeled decimal fields for a `Form` section, and an optional Fiber field for foods.
/// Targets never show fiber: it has no goal.
struct MacroFields: View {
  @Binding var model: MacroFieldsModel
  var basis: LocalizedStringKey = ""
  var showsFiber = false
  @State private var editedFields: Set<String> = []

  var body: some View {
    row("Calories", unit: "kcal", id: "caloriesField", text: $model.calories)
    row("Protein", unit: "g", id: "proteinField", text: $model.protein)
    row("Carbs", unit: "g", id: "carbsField", text: $model.carbs)
    row("Fat", unit: "g", id: "fatField", text: $model.fat)
    if showsFiber {
      row("Fiber", unit: "g", id: "fiberField", text: $model.fiber, isOptional: true)
    }
  }

  private func row(
    _ title: LocalizedStringKey, unit: LocalizedStringKey, id: String, text: Binding<String>,
    isOptional: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      LabeledContent {
        HStack(spacing: 4) {
          TextField(
            title, text: text,
            prompt: isOptional ? Text("Optional") : Text(verbatim: "0")
          )
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .fontDesign(.rounded)
          .monospacedDigit()
          .frame(minWidth: 44, minHeight: 44)
          .accessibilityLabel(Text(title) + Text(" ") + Text(basis))
          .accessibilityHint(
            isOptional ? Text("Optional. Leave empty if you don't know it.") : Text("")
          )
          .accessibilityIdentifier(id)
          .onChange(of: text.wrappedValue) { _, _ in editedFields.insert(id) }
          Text(unit).foregroundStyle(.secondary)
        }
      } label: {
        Text(title)
      }
      if let error = isOptional
        ? NumericInput.optionalNutritionError(text.wrappedValue)
        : NumericInput.nutritionError(text.wrappedValue),
        editedFields.contains(id)
      {
        Text(error).font(.footnote).foregroundStyle(Color.danger)
      }
    }
  }
}
