import EZHAKit
import SwiftUI

/// Signed-in shell. Phase 6 replaces this placeholder with the tab view.
struct MainShell: View {
  @Environment(AppModel.self) private var appModel

  var body: some View {
    NavigationStack {
      List {
        Section("Account") {
          Text(appModel.user?.email ?? "")
          Button("Sign out", role: .destructive) {
            Task { await appModel.signOut() }
          }
        }
      }
      .navigationTitle("Today")
    }
  }
}
