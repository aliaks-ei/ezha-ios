import AppIntents
import EZHAKit
import SwiftUI

/// "You have 1,460 kcal left. Protein 100 g, carbs 150 g, fat 50 g." from the widget snapshot.
struct CaloriesLeftIntent: AppIntent {
  static let title: LocalizedStringResource = "Calories left today"
  static let description = IntentDescription("Tells you the calories and macros left for today.")

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    guard let snapshot = SnapshotStore.read()?.asOf(.today()) else {
      return .result(
        dialog: "Open Ezha once to load today's totals.",
        view: Text("No data yet").padding())
    }
    let left = snapshot.remaining
    let n = { (value: Double) in max(0, value).formatted(.number.precision(.fractionLength(0))) }
    let dialog: IntentDialog =
      "You have \(n(left.calories)) kcal left. Protein \(n(left.protein)) g, carbs \(n(left.carbs)) g, fat \(n(left.fat)) g."
    return .result(dialog: dialog, view: CaloriesLeftSnippet(snapshot: snapshot))
  }
}

private struct CaloriesLeftSnippet: View {
  var snapshot: WidgetSnapshot

  var body: some View {
    HStack(spacing: 16) {
      MacroRing(goal: snapshot.goals.calories, eaten: snapshot.totals.calories)
        .frame(width: 120, height: 120)
        .scaleEffect(0.7)
      VStack(alignment: .leading, spacing: 4) {
        Text(snapshot.targetName ?? "Today").font(.headline)
        MacroLine(macros: snapshot.remaining.rounded).font(.subheadline)
        Text("left today").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding()
  }
}

struct EZHAShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenLoggerIntent(),
      phrases: ["Log a meal in \(.applicationName)", "Add food to \(.applicationName)"],
      shortTitle: "Log meal",
      systemImageName: "plus.circle")
    AppShortcut(
      intent: CaloriesLeftIntent(),
      phrases: [
        "Calories left in \(.applicationName)", "How many calories are left in \(.applicationName)",
      ],
      shortTitle: "Calories left",
      systemImageName: "flame")
    AppShortcut(
      intent: LogSavedFoodIntent(),
      phrases: ["Log \(\.$food) in \(.applicationName)", "Add \(\.$food) to \(.applicationName)"],
      shortTitle: "Log saved food",
      systemImageName: "books.vertical")
  }
}
