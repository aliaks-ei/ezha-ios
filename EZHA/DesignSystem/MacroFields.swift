import EZHAKit
import SwiftUI

/// Text state for four macro fields (calories, protein, carbs, fat).
struct MacroFieldsModel: Equatable {
  var calories: String
  var protein: String
  var carbs: String
  var fat: String

  init(values: MacroTotals) {
    calories = Macros.format(values.calories, maxFractionDigits: 1)
    protein = Macros.format(values.protein, maxFractionDigits: 1)
    carbs = Macros.format(values.carbs, maxFractionDigits: 1)
    fat = Macros.format(values.fat, maxFractionDigits: 1)
  }

  init(empty: Void = ()) {
    calories = ""
    protein = ""
    carbs = ""
    fat = ""
  }

  /// The parsed values, or nil when any field is not a number ≥ 0.
  var values: MacroTotals? {
    let parsed = [calories, protein, carbs, fat].map(parseNumberInput)
    guard parsed.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
    return MacroTotals(
      calories: parsed[0] ?? 0, protein: parsed[1] ?? 0, carbs: parsed[2] ?? 0, fat: parsed[3] ?? 0)
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

/// Four labeled decimal fields for a `Form` section.
struct MacroFields: View {
  @Binding var model: MacroFieldsModel

  var body: some View {
    row("Calories", unit: "kcal", text: $model.calories)
    row("Protein", unit: "g", text: $model.protein)
    row("Carbs", unit: "g", text: $model.carbs)
    row("Fat", unit: "g", text: $model.fat)
  }

  private func row(_ title: LocalizedStringKey, unit: LocalizedStringKey, text: Binding<String>)
    -> some View
  {
    LabeledContent {
      HStack(spacing: 4) {
        TextField(title, text: text, prompt: Text(verbatim: "0"))
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .fontDesign(.rounded)
          .monospacedDigit()
        Text(unit).foregroundStyle(.secondary)
      }
    } label: {
      Text(title)
    }
  }
}
