import EZHAKit
import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
  var date: Date
  var snapshot: WidgetSnapshot
  /// True when there is no snapshot yet (signed out or never loaded).
  var isPlaceholder = false
}

/// Reads the App Group snapshot. One entry now, one at the next local midnight with zero totals.
struct SnapshotProvider: TimelineProvider {
  func placeholder(in context: Context) -> SnapshotEntry {
    SnapshotEntry(date: .now, snapshot: .sample, isPlaceholder: true)
  }

  func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : current())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
    let now = current()
    let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
    var next = now.snapshot
    next.date = DateKey(midnight)
    next.totals = .zero
    completion(
      Timeline(
        entries: [
          now, SnapshotEntry(date: midnight, snapshot: next, isPlaceholder: now.isPlaceholder),
        ],
        policy: .atEnd))
  }

  private func current() -> SnapshotEntry {
    guard let snapshot = SnapshotStore.read() else {
      return SnapshotEntry(
        date: .now,
        snapshot: WidgetSnapshot(
          date: .today(), targetName: nil, goals: .zero, totals: .zero, updatedAt: .now),
        isPlaceholder: true)
    }
    return SnapshotEntry(date: .now, snapshot: snapshot.asOf(.today()))
  }
}

struct CaloriesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CaloriesWidget", provider: SnapshotProvider()) { entry in
      CaloriesWidgetView(entry: entry)
        .containerBackground(for: .widget) { Color.surface }
        .widgetURL(URL(string: "ezha://today"))
    }
    .configurationDisplayName("Calories left")
    .description("Calories and macros left today.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline,
    ])
  }
}

/// Reads the family from the environment and passes it on.
struct CaloriesWidgetView: View {
  var entry: SnapshotEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    CaloriesWidgetContent(entry: entry, family: family)
  }
}

struct CaloriesWidgetContent: View {
  var entry: SnapshotEntry
  var family: WidgetFamily

  private var snapshot: WidgetSnapshot { entry.snapshot }
  private var status: (value: Double, isOver: Bool) {
    Macros.calorieStatus(goal: snapshot.goals.calories, eaten: snapshot.totals.calories)
  }
  private var kcalText: Text {
    let value = Text(status.value, format: .number.precision(.fractionLength(0)))
    return status.isOver ? Text("\(value) kcal over") : Text("\(value) kcal left")
  }

  var body: some View {
    switch family {
    case .accessoryInline:
      kcalText
    case .accessoryCircular:
      Gauge(
        value: min(snapshot.totals.calories, max(snapshot.goals.calories, 1)),
        in: 0...max(snapshot.goals.calories, 1)
      ) {
        Image(systemName: "flame")
      } currentValueLabel: {
        Text(status.value, format: .number.precision(.fractionLength(0)))
          .monospacedDigit()
      }
      .gaugeStyle(.accessoryCircular)
      .widgetAccentable()
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 2) {
        kcalText.font(.headline).widgetAccentable()
        let left = snapshot.remaining
        Text(
          "P \(max(0, left.protein), format: .number.precision(.fractionLength(0))) · C \(max(0, left.carbs), format: .number.precision(.fractionLength(0))) · F \(max(0, left.fat), format: .number.precision(.fractionLength(0)))"
        )
        .font(.caption)
        .monospacedDigit()
      }
    case .systemMedium:
      HStack(spacing: 16) {
        WidgetRing(snapshot: snapshot)
        VStack(alignment: .leading, spacing: 8) {
          WidgetBar(
            title: "Protein", goal: snapshot.goals.protein, eaten: snapshot.totals.protein,
            color: .brandSecondary)
          WidgetBar(
            title: "Carbs", goal: snapshot.goals.carbs, eaten: snapshot.totals.carbs,
            color: .brandAccent)
          WidgetBar(
            title: "Fat", goal: snapshot.goals.fat, eaten: snapshot.totals.fat, color: .brandPrimary
          )
          Link(destination: URL(string: "ezha://log")!) {
            Label("Log", systemImage: "plus")
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 10)
              .padding(.vertical, 4)
              .foregroundStyle(Color.brandPrimary)
              .background(Color.brandPrimary.opacity(0.18), in: .capsule)
          }
          .widgetAccentable()
        }
      }
    default:
      WidgetRing(snapshot: snapshot)
    }
  }
}

/// The calorie ring for widgets.
struct WidgetRing: View {
  var snapshot: WidgetSnapshot
  @Environment(\.widgetRenderingMode) private var renderingMode

  var body: some View {
    let status = Macros.calorieStatus(
      goal: snapshot.goals.calories, eaten: snapshot.totals.calories)
    let progress =
      snapshot.goals.calories > 0 ? min(snapshot.totals.calories / snapshot.goals.calories, 1) : 0
    ZStack {
      Circle().stroke(Color.track, lineWidth: 12)
      Circle()
        .trim(from: 0, to: status.isOver ? 1 : progress)
        .stroke(
          renderingMode == .fullColor
            ? AnyShapeStyle(
              AngularGradient(
                colors: [.brandSecondary, .brandPrimary], center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(360 * max(status.isOver ? 1 : progress, 0.01))))
            : AnyShapeStyle(.tint),
          style: StrokeStyle(lineWidth: 12, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .widgetAccentable()
      VStack(spacing: 0) {
        Text(status.value, format: .number.precision(.fractionLength(0)))
          .font(.system(.title2, design: .rounded, weight: .bold))
          .monospacedDigit()
          .minimumScaleFactor(0.6)
          .foregroundStyle(status.isOver ? Color.danger : Color.primary)
        Text(status.isOver ? "kcal over" : "kcal left")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(14)
    }
    .padding(4)
  }
}

struct WidgetBar: View {
  var title: LocalizedStringKey
  var goal: Double
  var eaten: Double
  var color: Color

  var body: some View {
    let remaining = (goal - eaten).rounded()
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(title).font(.caption2.weight(.semibold))
        Spacer()
        Text(
          "\(abs(remaining), format: .number.precision(.fractionLength(0))) g \(remaining < 0 ? "over" : "left")"
        )
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(remaining < 0 ? Color.danger : Color.secondary)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.track)
          Capsule().fill(color)
            .frame(
              width: proxy.size.width * Double(Macros.barPercent(eaten: eaten, target: goal)) / 100
            )
            .widgetAccentable()
        }
      }
      .frame(height: 5)
    }
  }
}

#Preview(as: .systemSmall) {
  CaloriesWidget()
} timeline: {
  SnapshotEntry(date: .now, snapshot: .sample)
  SnapshotEntry(
    date: .now,
    snapshot: WidgetSnapshot(
      date: .today(), targetName: "Basic", goals: .example,
      totals: MacroTotals(calories: 2400, protein: 150, carbs: 260, fat: 90), updatedAt: .now))
}

#Preview(as: .systemMedium) {
  CaloriesWidget()
} timeline: {
  SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview(as: .accessoryCircular) {
  CaloriesWidget()
} timeline: {
  SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview(as: .accessoryRectangular) {
  CaloriesWidget()
} timeline: {
  SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview(as: .accessoryInline) {
  CaloriesWidget()
} timeline: {
  SnapshotEntry(date: .now, snapshot: .sample)
}
