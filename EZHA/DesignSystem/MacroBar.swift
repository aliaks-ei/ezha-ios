import EZHAKit
import SwiftUI

/// One macro: remaining "left" or "over", a capsule bar, and "40 / 140 g eaten".
struct MacroBar: View {
  var title: LocalizedStringKey
  var goal: Double
  var eaten: Double
  var color: Color

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false

  private var remaining: Double { (goal - eaten).rounded() }

  private var titleText: some View {
    Text(title).font(.subheadline.weight(.semibold))
  }

  private var remainingText: some View {
    let value = Text("\(abs(remaining), format: .number.precision(.fractionLength(0))) g")
      .fontWeight(.semibold)
      .foregroundStyle(remaining < 0 ? Color.danger : Color.primary)
    let word = Text(remaining < 0 ? "over" : "left").foregroundStyle(.secondary)
    return Text("\(value) \(word)")
      .font(.subheadline)
      .fontDesign(.rounded)
      .monospacedDigit()
      .contentTransition(.numericText(value: remaining))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Side by side when it fits; stacked at large text sizes.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline) {
          titleText.fixedSize()
          Spacer()
          remainingText.fixedSize()
        }
        VStack(alignment: .leading, spacing: 2) {
          titleText
          remainingText
        }
      }
      GeometryReader { proxy in
        let percent = Double(Macros.barPercent(eaten: eaten, target: goal)) / 100
        ZStack(alignment: .leading) {
          Capsule().fill(Color.track)
          Capsule().fill(color)
            .frame(width: proxy.size.width * (hasAppeared ? percent : 0))
        }
      }
      .frame(height: 8)
      Text(
        "\(eaten, format: .number.precision(.fractionLength(0))) / \(goal, format: .number.precision(.fractionLength(0))) g eaten"
      )
      .font(.caption)
      .fontDesign(.rounded)
      .monospacedDigit()
      .foregroundStyle(.secondary)
    }
    .animation(
      reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.8, bounce: 0.15), value: eaten
    )
    .animation(
      reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.8, bounce: 0.15),
      value: hasAppeared
    )
    .onAppear { hasAppeared = true }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(title))
    .accessibilityValue(
      Text(
        "\(eaten, format: .number.precision(.fractionLength(0))) of \(goal, format: .number.precision(.fractionLength(0))) grams eaten. \(abs(remaining), format: .number.precision(.fractionLength(0))) \(remaining < 0 ? "over" : "left")."
      ))
  }
}

/// "P 40g · C 70g · F 20g"
struct MacroLine: View {
  var macros: MacroTotals

  var body: some View {
    Text(
      "P \(macros.protein, format: .number.precision(.fractionLength(0)))g · C \(macros.carbs, format: .number.precision(.fractionLength(0)))g · F \(macros.fat, format: .number.precision(.fractionLength(0)))g"
    )
    .fontDesign(.rounded)
    .monospacedDigit()
    .accessibilityLabel(
      Text(
        "Protein \(macros.protein, format: .number.precision(.fractionLength(0))) grams, carbs \(macros.carbs, format: .number.precision(.fractionLength(0))) grams, fat \(macros.fat, format: .number.precision(.fractionLength(0))) grams"
      ))
  }
}

/// "640 kcal"
struct KcalText: View {
  var value: Double

  var body: some View {
    Text("\(value, format: .number.precision(.fractionLength(0))) kcal")
      .fontDesign(.rounded)
      .monospacedDigit()
  }
}

#Preview {
  VStack(spacing: 20) {
    MacroBar(title: "Protein", goal: 140, eaten: 40, color: .brandSecondary)
    MacroBar(title: "Fat", goal: 70, eaten: 90, color: .brandPrimary)
    MacroLine(macros: MacroTotals(calories: 640, protein: 40, carbs: 70, fat: 20))
  }
  .padding()
}
