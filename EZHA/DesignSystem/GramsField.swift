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
      Button {
        decrements += 1
        onStep(-step)
      } label: {
        Image(systemName: "minus").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
      }
      .buttonRepeatBehavior(.enabled)
      .accessibilityLabel("Decrease")

      HStack(spacing: 2) {
        TextField("Grams", text: $text)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .fontDesign(.rounded)
          .monospacedDigit()
          .focused($isFocused)
          .fixedSize()
          .frame(minWidth: 44, alignment: .trailing)
        Text(unit).foregroundStyle(.secondary)
      }

      Button {
        increments += 1
        onStep(step)
      } label: {
        Image(systemName: "plus").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
      }
      .buttonRepeatBehavior(.enabled)
      .accessibilityLabel("Increase")
    }
    .buttonStyle(.borderless)
    .sensoryFeedback(.increase, trigger: increments)
    .sensoryFeedback(.decrease, trigger: decrements)
    .onChange(of: isFocused) { _, focused in
      if !focused { onFocusLost() }
    }
  }
}
