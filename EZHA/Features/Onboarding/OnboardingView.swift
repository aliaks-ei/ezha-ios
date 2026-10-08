import EZHAKit
import SwiftUI

/// Shown after sign-in when the user's only target has all zeros.
/// Steps: daily target (skipped if a non-zero target exists), AI consent, finish.
struct OnboardingView: View {
  enum Step {
    case target
    case consent
  }

  @Environment(AppModel.self) private var appModel
  @State private var step = Step.target
  @State private var macros = MacroFieldsModel(values: .example)
  @State private var errorMessage: String?
  @State private var isSaving = false

  private var basicTarget: DailyTarget? { appModel.onboardingTargets.first }
  private var needsTarget: Bool { basicTarget?.macros.isAllZero ?? true }

  var body: some View {
    NavigationStack {
      Group {
        switch step {
        case .target: targetStep
        case .consent: consentStep
        }
      }
      .background(BrandBackground(intensity: 0.15))
      .animation(.smooth, value: step)
    }
    .onAppear { if !needsTarget { step = .consent } }
  }

  private var targetStep: some View {
    Form {
      Section {
        Text("Starting values — adjust to your own target.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("startingTargetExplanation")
        MacroFields(model: $macros, basis: "per day")
      } header: {
        Text("Calories and macros per day")
      } footer: {
        Text("Macros add up to \(Macros.format(macros.macroCalories, maxFractionDigits: 0)) kcal")
          .monospacedDigit()
      }
      if let errorMessage {
        Section {
          Text(errorMessage).foregroundStyle(Color.danger)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .navigationTitle("Set your daily target")
    .safeAreaInset(edge: .bottom) {
      Button {
        Task { await saveTarget() }
      } label: {
        Group {
          if isSaving { ProgressView() } else { Text("Continue").bold() }
        }
        .frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
      .disabled(macros.values == nil || isSaving)
      .padding()
    }
  }

  private var consentStep: some View {
    AIConsentView(
      onAllow: {
        appModel.aiConsent = .allowed
        appModel.finishOnboarding()
      },
      onDecline: {
        appModel.aiConsent = .declined
        appModel.finishOnboarding()
      }
    )
    .navigationTitle("AI features")
  }

  private func saveTarget() async {
    guard let values = macros.values else { return }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    do {
      _ = try await appModel.clients.targets.save(
        basicTarget?.id, basicTarget?.name ?? "Basic", values, appModel.today)
      if appModel.aiConsent == .undecided {
        step = .consent
      } else {
        appModel.finishOnboarding()
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

#Preview {
  OnboardingView()
    .environment(AppModel(clients: .preview))
}
