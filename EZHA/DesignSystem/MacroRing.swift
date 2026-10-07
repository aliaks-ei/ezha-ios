import EZHAKit
import SwiftUI

/// Calorie ring: brand gradient, "kcal left" or "kcal over" in the center.
/// When over, the ring is full and a `Danger` glow pulses once.
struct MacroRing: View {
  var goal: Double
  var eaten: Double

  @ScaledMetric private var size: CGFloat
  @ScaledMetric private var lineWidth: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false

  /// `diameter` is at the default text size. It scales with Dynamic Type.
  init(goal: Double, eaten: Double, diameter: CGFloat = 168) {
    self.goal = goal
    self.eaten = eaten
    _size = ScaledMetric(wrappedValue: diameter, relativeTo: .largeTitle)
    _lineWidth = ScaledMetric(wrappedValue: (diameter / 10.5).rounded(), relativeTo: .largeTitle)
  }

  private var isCompact: Bool { size < 150 }

  private var status: (value: Double, isOver: Bool) {
    Macros.calorieStatus(goal: goal, eaten: eaten)
  }

  private var progress: Double {
    guard goal > 0 else { return 0 }
    return min(eaten / goal, 1)
  }

  var body: some View {
    let status = status
    ZStack {
      Circle()
        .stroke(Color.track, lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: hasAppeared ? (status.isOver ? 1 : progress) : 0)
        .stroke(
          AngularGradient(
            colors: [.brandSecondary, .brandPrimary], center: .center,
            startAngle: .degrees(0), endAngle: .degrees(360 * max(progress, 0.01))),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
      if status.isOver && !reduceMotion {
        Circle()
          .stroke(Color.danger, lineWidth: lineWidth / 2)
          .padding(-lineWidth)
          .phaseAnimator([0.0, 0.8, 0.0], trigger: status.isOver) { view, opacity in
            view.opacity(opacity).blur(radius: lineWidth / 2)
          } animation: { _ in
            .easeInOut(duration: 0.6)
          }
      }
      VStack(spacing: 0) {
        Text(status.value, format: .number.precision(.fractionLength(0)))
          .font(.system(isCompact ? .title : .largeTitle, design: .rounded, weight: .bold))
          .monospacedDigit()
          .contentTransition(.numericText(value: status.value))
          .foregroundStyle(status.isOver ? Color.danger : Color.primary)
          .minimumScaleFactor(0.5)
          .lineLimit(1)
        Text(status.isOver ? "kcal over" : "kcal left")
          .font(isCompact ? .footnote : .subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(lineWidth * (isCompact ? 1.2 : 1.5))
    }
    .frame(width: size, height: size)
    .animation(
      reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.8, bounce: 0.15), value: eaten
    )
    .animation(
      reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.8, bounce: 0.15), value: goal
    )
    .animation(
      reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.8, bounce: 0.15),
      value: hasAppeared
    )
    .onAppear { hasAppeared = true }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: Text {
    let eatenText = eaten.formatted(.number.precision(.fractionLength(0)))
    let goalText = goal.formatted(.number.precision(.fractionLength(0)))
    let value = status.value.formatted(.number.precision(.fractionLength(0)))
    return status.isOver
      ? Text("\(eatenText) of \(goalText) calories eaten. \(value) over.")
      : Text("\(eatenText) of \(goalText) calories eaten. \(value) left.")
  }
}

#Preview {
  VStack(spacing: 32) {
    MacroRing(goal: 2100, eaten: 640)
    MacroRing(goal: 2100, eaten: 2400)
  }
}
