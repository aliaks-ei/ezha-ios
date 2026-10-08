import EZHAKit
import SwiftUI

/// Shows one screen with fixture data. UI tests pick it with launch environment values:
/// HARNESS_SCENARIO (see `LoggerFixtures.state`, plus "today" and "libraryTab"),
/// HARNESS_APPEARANCE ("light" or "dark"), HARNESS_LARGE_TEXT ("1" for accessibility3).
@main
struct HarnessApp: App {
  @State private var app: AppModel
  @State private var presented = false
  private let scenario: String
  private let appearance: ColorScheme
  private let size: DynamicTypeSize

  init() {
    let env = ProcessInfo.processInfo.environment
    let scenario = env["HARNESS_SCENARIO"] ?? "review"
    self.scenario = scenario
    appearance = env["HARNESS_APPEARANCE"] == "dark" ? .dark : .light
    size =
      env["HARNESS_LARGE_TEXT"] == "1"
      ? (env["HARNESS_TEXT_SIZE"] == "AX5" ? .accessibility5 : .accessibility3) : .large
    _app = State(initialValue: LoggerFixtures.app(scenario))
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if scenario == "today" || scenario == "todayOver" {
          TodayView(openLogger: { _ in })
        } else if scenario == "shell" {
          MainShell()
        } else if scenario == "settings" {
          SettingsView()
        } else if scenario.hasPrefix("suggestions") {
          SuggestionsView()
        } else if scenario == "auth" {
          AuthView()
        } else if scenario == "onboarding" {
          OnboardingView()
        } else if scenario == "consent" {
          NavigationStack {
            AIConsentView(onAllow: {}, onDecline: {})
              .navigationTitle("AI features")
          }
        } else if scenario == "addFood" {
          AddFoodSheet()
        } else if scenario == "foodEditor" {
          FoodEditorSheet(food: PreviewData.foods[0])
        } else if scenario == "mealEditor" {
          MealEditorSheet(meal: PreviewData.foods[2])
        } else if scenario == "libraryTab" {
          LibraryView().overlay { ToastOverlay(toast: $app.toast) }
        } else {
          logger
        }
      }
      .environment(app)
      .environment(\.dynamicTypeSize, size)
      .preferredColorScheme(appearance)
      .tint(Color.brandPrimary)
    }
  }

  private var logger: some View {
    Button("Open logger") { presented = true }
      .overlay { ToastOverlay(toast: $app.toast) }
      .sheet(isPresented: $presented) {
        LoggerView(date: LoggerFixtures.date, drafts: draftAccess)
          .environment(\.dynamicTypeSize, size)
      }
      .task {
        try? await app.sync.draftStore.save(
          LoggerFixtures.date,
          state: JSONEncoder.ezha.encode(LoggerFixtures.state(scenario)),
          imageData: scenario == "photoDraft" ? LoggerFixtures.photo : nil)
        await app.dayStore.load(LoggerFixtures.date)
        presented = true
      }
  }
  private var draftAccess: LoggerDraftAccess? {
    guard scenario == "draftFailure" else { return nil }
    let live = LoggerDraftAccess.live(app.sync.draftStore)
    return LoggerDraftAccess(
      load: live.load,
      save: { _, _, _ in throw AIError.message("Storage unavailable") },
      delete: live.delete)
  }

}

enum Appearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }

  var title: LocalizedStringKey {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }
}
