import EZHAKit
import SwiftUI

/// Signed-in shell: four tabs, the "Log meal" accessory, the toast, and the logger sheet.
struct MainShell: View {
  @Environment(AppModel.self) private var appModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var loggerDate: DateKey?

  var body: some View {
    @Bindable var appModel = appModel
    TabView(selection: $appModel.selectedTab) {
      Tab("Today", systemImage: "sun.max", value: AppModel.Tab.today) {
        TodayView(openLogger: openLogger)
      }
      Tab("Suggestions", systemImage: "sparkles", value: AppModel.Tab.suggestions) {
        SuggestionsView()
      }
      Tab("Library", systemImage: "books.vertical", value: AppModel.Tab.library) {
        LibraryView()
      }
      Tab("Settings", systemImage: "gearshape", value: AppModel.Tab.settings) {
        SettingsView()
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory {
      LogAccessory(openLogger: { openLogger() })
    }
    .overlay { ToastOverlay(toast: $appModel.toast).padding(.bottom, 110) }
    .sheet(item: $loggerDate) { date in
      // No zoom transition: dismissing a zoom sheet whose source is in the tab bar
      // accessory hits a UIKit assertion (_morphPreviewFromCurrentState) on iOS 26.4.
      LoggerView(date: date)
    }
    .task {
      await appModel.sync.refresh()
      await appModel.sync.run()
      await appModel.targetsStore.load()
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      appModel.refreshToday()
      Task { await appModel.sync.run() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
      appModel.refreshToday()
    }
    .onChange(of: appModel.isLoggerRequested, initial: true) { _, requested in
      guard requested else { return }
      appModel.isLoggerRequested = false
      openLogger()
    }
  }

  private func openLogger(_ date: DateKey? = nil) {
    loggerDate = date ?? appModel.selectedDate
  }
}

/// "+ Log meal · 1,460 kcal left"
struct LogAccessory: View {
  @Environment(AppModel.self) private var appModel
  var openLogger: () -> Void

  var body: some View {
    let bundle = appModel.dayStore.merged(appModel.selectedDate)
    Button(action: openLogger) {
      HStack(spacing: 8) {
        Image(systemName: "plus.circle.fill")
          .foregroundStyle(Color.brandPrimary)
          .font(.title3)
        Text("Log meal").fontWeight(.semibold)
        if let bundle {
          let status = Macros.calorieStatus(
            goal: bundle.goals.calories, eaten: bundle.totals.calories)
          Text("·").foregroundStyle(.secondary)
          Text(
            status.isOver
              ? "\(status.value, format: .number.precision(.fractionLength(0))) kcal over"
              : "\(status.value, format: .number.precision(.fractionLength(0))) kcal left"
          )
          .foregroundStyle(.secondary)
          .fontDesign(.rounded)
          .monospacedDigit()
          .contentTransition(.numericText(value: status.value))
        }
      }
      .frame(maxWidth: .infinity)
      .frame(minHeight: 44)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("logAccessory")
  }
}
