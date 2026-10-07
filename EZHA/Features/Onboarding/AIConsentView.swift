import EZHAKit
import SwiftUI

/// Explains what AI features send, with "Allow" and "Not now" (guide 9.4).
struct AIConsentView: View {
  var onAllow: () -> Void
  var onDecline: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Image(systemName: "sparkles")
          .font(.largeTitle)
          .foregroundStyle(Color.brandPrimary)
          .accessibilityHidden(true)
        Text(
          "Photos and descriptions are sent to our server and to OpenAI to estimate nutrition and suggest meals."
        )
        .font(.title3)
        VStack(alignment: .leading, spacing: 12) {
          Label(
            "Only what you add to a meal or a suggestion request is sent.", systemImage: "photo")
          Label(
            "Your saved library and manual logging work without AI.", systemImage: "books.vertical")
          Label("You can change this any time in Settings.", systemImage: "gearshape")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      .padding()
      .frame(maxWidth: 600, alignment: .leading)
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 8) {
        Button(action: onAllow) {
          Text("Allow").bold().frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        Button(action: onDecline) {
          Text("Not now").frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
      }
      .padding()
    }
  }
}

/// Asks for AI consent in an alert before an AI action. Runs the action on "Allow".
/// An alert, not a sheet: these actions start from sheets, and sheets must not stack (HIG).
private struct AIConsentAlert: ViewModifier {
  @Binding var action: (() -> Void)?
  @Environment(AppModel.self) private var appModel

  func body(content: Content) -> some View {
    content.alert(
      "Allow AI features?",
      isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }),
      presenting: action
    ) { action in
      Button("Not now", role: .cancel) { appModel.aiConsent = .declined }
      Button("Allow") {
        appModel.aiConsent = .allowed
        action()
      }
      .keyboardShortcut(.defaultAction)
    } message: { _ in
      Text(
        "Photos and descriptions you add are sent to our server and to OpenAI to estimate nutrition and suggest meals. Your library and manual logging work without AI. You can change this in Settings."
      )
    }
  }
}

extension View {
  /// Shows the AI consent alert while `action` is set.
  func aiConsentAlert(_ action: Binding<(() -> Void)?>) -> some View {
    modifier(AIConsentAlert(action: action))
  }
}

#Preview {
  AIConsentView(onAllow: {}, onDecline: {})
}
