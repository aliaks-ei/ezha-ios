import EZHAKit
import SwiftUI

/// Today's water: amount drunk, target status, a bar, and quick-add buttons.
/// Water never changes calories or macros.
struct WaterCard: View {
  var drunk: Double
  var target: Double?
  var presets: [WaterPreset]
  var add: (WaterPreset) -> Void
  var addOther: () -> Void
  /// Opens the target editor. Shown only without a target.
  var setTarget: () -> Void
  /// Amount, status, and bar only: no buttons. For the entries sheet.
  var isCompact = false

  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var status: Water.Status { Water.status(drunk: drunk, target: target) }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      let line =
        typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
      line {
        amount
          .frame(maxWidth: typeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
        statusText
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("waterSummary")

      if let target, target > 0 {
        bar(Water.progress(drunk: drunk, target: target))
      } else if !isCompact {
        noTarget
      }

      if !isCompact { quickAdd }
    }
    .padding(.vertical, 6)
    .animation(
      reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.15), value: drunk)
  }

  private var quickAdd: some View {
    FlowLayout(spacing: 8) {
      ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
        chip(
          title: Water.format(preset.amountMl), systemImage: "drop.fill",
          label: "Add \(preset.name), \(Water.format(preset.amountMl))",
          id: "waterQuickAdd\(index)"
        ) { add(preset) }
      }
      chip(
        title: String(localized: "Other"), systemImage: "plus", label: "Add another amount",
        id: "waterOther", action: addOther)
    }
    .padding(.top, 2)
  }

  /// "1,250 of 2,000 ml", or "1,250 ml today" without a target.
  private var amount: some View {
    let value = Text(Water.number(drunk))
      .font(.title.weight(.bold))
      .foregroundStyle(Color.primary)
    let rest =
      if let target, target > 0 {
        Text("of \(Water.format(target))")
      } else {
        Text("ml today")
      }
    return Text("\(value) \(rest.font(.subheadline).foregroundStyle(.secondary))")
      .fontDesign(.rounded)
      .monospacedDigit()
      .contentTransition(.numericText(value: drunk))
      .accessibilityIdentifier("waterAmount")
  }

  @ViewBuilder private var statusText: some View {
    switch status {
    case .noTarget:
      EmptyView()
    case .left(let ml):
      remaining(Water.format(ml), word: Text("left"))
    case .over(let ml):
      remaining(Water.format(ml), word: Text("over"))
    case .reached:
      HStack(spacing: 4) {
        Image(systemName: "checkmark")
          .fontWeight(.bold)
          .foregroundStyle(Color.water)
          .accessibilityHidden(true)
        Text("Target reached")
          .fontWeight(.semibold)
      }
      .font(.subheadline)
    }
  }

  private func remaining(_ value: String, word: Text) -> some View {
    let number = Text(value).fontWeight(.semibold).foregroundStyle(Color.primary)
    return Text("\(number) \(word.foregroundStyle(.secondary))")
      .font(.subheadline)
      .fontDesign(.rounded)
      .monospacedDigit()
      .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
  }

  private func bar(_ progress: Double) -> some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.water.opacity(0.18))
        Capsule().fill(Color.water)
          .frame(width: proxy.size.width * progress)
      }
    }
    .frame(height: 10)
    .accessibilityHidden(true)
  }

  private var noTarget: some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
      : AnyLayout(HStackLayout(spacing: 6))
    return layout {
      Text("No daily water target.")
        .foregroundStyle(.secondary)
      Button("Set target", action: setTarget)
        .fontWeight(.semibold)
        .foregroundStyle(Color.brandPrimary)
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .accessibilityIdentifier("waterSetTarget")
    }
    .font(.footnote)
  }

  private func chip(
    title: String, systemImage: String, label: LocalizedStringKey, id: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .foregroundStyle(systemImage == "plus" ? Color.primary : Color.water)
          .accessibilityHidden(true)
        Text(title)
          .foregroundStyle(Color.primary)
      }
      .font(.subheadline.weight(.semibold))
      .fontDesign(.rounded)
      .monospacedDigit()
      .padding(.horizontal, 14)
      .frame(minHeight: 44)
      .background(Color(.tertiarySystemFill), in: .capsule)
      .contentShape(.capsule)
    }
    // Borderless: each button in the row is its own tap target.
    .buttonStyle(.borderless)
    .accessibilityLabel(label)
    .accessibilityIdentifier(id)
  }
}

/// "Water          4 entries ›". The button shows only when there are entries.
struct WaterHeader: View {
  var count: Int
  var showEntries: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    layout {
      Text("Water")
        .font(.title3.weight(.semibold))
        .foregroundStyle(Color.primary)
        .accessibilityAddTraits(.isHeader)
      if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
      if count > 0 {
        Button(action: showEntries) {
          HStack(spacing: 4) {
            Text(count == 1 ? "1 entry" : "\(count) entries")
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .accessibilityHidden(true)
          }
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Color.brandPrimary)
          .frame(minHeight: 44)
          .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(count == 1 ? "1 water entry" : "\(count) water entries")
        .accessibilityHint("Edit or delete water entries")
        .accessibilityIdentifier("waterEntriesButton")
      }
    }
    .textCase(nil)
  }
}
