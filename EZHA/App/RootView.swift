import EZHAKit
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var appModel

  var body: some View {
    @Bindable var appModel = appModel
    ZStack {
      switch appModel.session {
      case .loading:
        BrandBackground()
      case .signedOut:
        AuthView()
          .transition(.opacity)
      case .onboarding:
        OnboardingView()
          .transition(.opacity)
      case .signedIn:
        MainShell()
          .transition(.opacity)
      }
    }
    .animation(.smooth(duration: 0.3), value: appModel.session)
    .sheet(isPresented: $appModel.isPasswordRecoveryPresented) {
      NewPasswordSheet()
    }
    .alert(
      "Link failed",
      isPresented: Binding(
        get: { appModel.linkError != nil }, set: { if !$0 { appModel.linkError = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(appModel.linkError ?? "")
    }
  }
}

#Preview {
  RootView()
    .environment(AppModel(clients: .preview))
}
