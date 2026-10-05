import EZHAKit
import SwiftUI

/// A decimal grams field with − and + buttons that repeat while held.
struct GramsField: View {
  @Binding var text: String
  var onStep: (Double) -> Void
  var onFocusLost: () -> Void
  var unit: LocalizedStringKey = "g"
  var step: Double = LogItemMath.stepGrams

  @FocusState private var isFocused: Bool
  @State private var increments = 0
  @State private var decrements = 0

  var body: some View {
    HStack(spacing: 4) {
      Button("Decrease", systemImage: "minus") {
        decrements += 1
        onStep(-step)
      }
      .labelStyle(.iconOnly)
      .buttonRepeatBehavior(.enabled)
      .frame(width: 44, height: 44)
      .contentShape(.rect)

      HStack(spacing: 2) {
        TextField("Grams", text: $text)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .fontDesign(.rounded)
          .monospacedDigit()
          .focused($isFocused)
          .frame(minWidth: 44, maxWidth: 80)
        Text(unit).foregroundStyle(.secondary)
      }

      Button("Increase", systemImage: "plus") {
        increments += 1
        onStep(step)
      }
      .labelStyle(.iconOnly)
      .buttonRepeatBehavior(.enabled)
      .frame(width: 44, height: 44)
      .contentShape(.rect)
    }
    .buttonStyle(.borderless)
    .sensoryFeedback(.increase, trigger: increments)
    .sensoryFeedback(.decrease, trigger: decrements)
    .onChange(of: isFocused) { _, focused in
      if !focused { onFocusLost() }
    }
  }
}
