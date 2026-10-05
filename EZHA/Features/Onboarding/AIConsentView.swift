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

/// The consent sheet shown before an AI action when consent is not given.
struct AIConsentSheet: View {
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  var onAllowed: () -> Void = {}

  var body: some View {
    NavigationStack {
      AIConsentView(
        onAllow: {
          appModel.aiConsent = .allowed
          dismiss()
          onAllowed()
        },
        onDecline: {
          appModel.aiConsent = .declined
          dismiss()
        }
      )
      .navigationTitle("AI features")
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.medium, .large])
  }
}

#Preview {
  AIConsentView(onAllow: {}, onDecline: {})
}
