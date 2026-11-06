import EZHAKit
import SwiftUI

/// A decimal amount field (g, ml or portions) with − and + buttons that repeat while held.
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
        TextField("Amount", text: $text)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .fontDesign(.rounded)
          .monospacedDigit()
          .focused($isFocused)
          .fixedSize()
          .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
          .accessibilityLabel(accessibilityName)
        Text(unit).foregroundStyle(.secondary).lineLimit(1).fixedSize()
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

extension AmountUnit {
  /// "g" or "ml", the visible unit after an amount field.
  var label: LocalizedStringKey { LocalizedStringKey(symbol) }

  /// Column heading: "Per 100 g" or "Per 100 ml".
  var per100Title: LocalizedStringKey { self == .ml ? "Per 100 ml" : "Per 100 g" }

  /// Inline text: "per 100 g" or "per 100 ml".
  var per100Text: LocalizedStringKey { self == .ml ? "per 100 ml" : "per 100 g" }

  /// Portion editor field title.
  var amountEatenTitle: LocalizedStringKey { self == .ml ? "Millilitres" : "Grams eaten" }
}
