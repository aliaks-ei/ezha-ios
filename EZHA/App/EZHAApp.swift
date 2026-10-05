import EZHAKit
import SwiftUI

@main
struct EZHAApp: App {
  @State private var appModel = AppModel(clients: .live)
  @AppStorage("appearance") private var appearance = Appearance.system

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(appModel)
        .preferredColorScheme(appearance.colorScheme)
        .tint(.brandPrimary)
        .task { await appModel.start() }
        .onOpenURL { url in Task { await appModel.handle(url) } }
    }
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
