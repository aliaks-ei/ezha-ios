import EZHAKit
import SwiftUI

/// Signed-in shell: four tabs, the "Log meal" tab bar button, the toast, and the logger sheet.
struct MainShell: View {
  @Environment(AppModel.self) private var appModel
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.colorScheme) private var colorScheme
  @State private var loggerDate: DateKey?

  var body: some View {
    @Bindable var appModel = appModel
    // Selecting the log tab opens the logger and keeps the current tab.
    let selection = Binding<AppModel.Tab>(
      get: { appModel.selectedTab },
      set: { tab in
        if tab == .log { openLogger() } else { appModel.selectedTab = tab }
      })
    TabView(selection: selection) {
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
      // The search role gives the separate round button at the trailing end of the tab bar,
      // in thumb reach and in the same row as the tabs. Used for the app's primary action.
      Tab(value: AppModel.Tab.log, role: .search) {
        Color.clear
      } label: {
        Label {
          Text("Log meal")
        } icon: {
          // The tab bar draws template icons in one neutral color. An original-mode image
          // keeps the brand color, so the primary action stands out.
          Image(uiImage: logIcon)
        }
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .sensoryFeedback(.success, trigger: appModel.logSuccessCount)
    .overlay { ToastOverlay(toast: $appModel.toast).padding(.bottom, 64) }
    .sheet(item: $loggerDate) { date in
      // No zoom transition: from the old tab bar accessory source it hit a UIKit assertion
      // (_morphPreviewFromCurrentState) on iOS 26.4. Not tried from the toolbar button.
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
      if OpenLoggerIntent.consumePendingRequest() { appModel.openLoggerForToday() }
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

  /// The brand color resolved for the current appearance: an original-mode image does not adapt.
  private var logIcon: UIImage {
    let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
    let color = UIColor(Color.brandPrimary).resolvedColor(with: traits)
    return UIImage(
      systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(weight: .semibold))?
      .withTintColor(color, renderingMode: .alwaysOriginal) ?? UIImage()
  }

  private func openLogger(_ date: DateKey? = nil) {
    loggerDate = date ?? appModel.selectedDate
  }
}
