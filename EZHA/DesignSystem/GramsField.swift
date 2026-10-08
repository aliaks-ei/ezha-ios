import EZHAKit
import SwiftUI

/// A decimal grams field with − and + buttons that repeat while held.
struct GramsField: View {
  @Binding var text: String
  var onStep: (Double) -> Void
  var onFocusLost: () -> Void
  var unit: LocalizedStringKey = "g"
  var step: Double = LogItemMath.stepGrams
  var accessibilityName: String = String(localized: "Portion in grams")

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
      .accessibilityLabel("Decrease \(accessibilityName)")

      HStack(spacing: 2) {
        TextField("Grams", text: $text)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .fontDesign(.rounded)
          .monospacedDigit()
          .focused($isFocused)
          .fixedSize()
          .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
          .accessibilityLabel(accessibilityName)
        Text(unit).foregroundStyle(.secondary)
      }
      .frame(minWidth: 44, minHeight: 44)
      .padding(.horizontal, 8)
      .background(Color.canvas, in: .rect(cornerRadius: 8))
      .contentShape(.rect)
      .onTapGesture { isFocused = true }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("portionInputRegion")

      Button {
        increments += 1
        onStep(step)
      } label: {
        Image(systemName: "plus").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
      }
      .buttonRepeatBehavior(.enabled)
      .accessibilityLabel("Increase \(accessibilityName)")
    }
    .buttonStyle(.borderless)
    .sensoryFeedback(.increase, trigger: increments)
    .sensoryFeedback(.decrease, trigger: decrements)
    .onChange(of: isFocused) { _, focused in
      if !focused { onFocusLost() }
    }
  }
}
