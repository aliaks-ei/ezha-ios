import EZHAKit
import Foundation
import Observation

/// Session state, the selected day, AI consent, and deep link routing.
@MainActor
@Observable
final class AppModel {
  enum Session: Equatable {
    case loading
    case signedOut
    case onboarding
    case signedIn
  }

  enum AIConsent: String {
    case undecided
    case allowed
    case declined
  }

  enum Tab: Hashable {
    case today
    case suggestions
    case library
    case settings
  }

  private(set) var session: Session = .loading
  private(set) var user: AccountUser?
  /// Targets loaded for onboarding. The "Basic" target is the first one.
  private(set) var onboardingTargets: [DailyTarget] = []
  var today = DateKey.today()
  var selectedDate = DateKey.today()
  var selectedTab: Tab = .today
  var isPasswordRecoveryPresented = false
  /// Set by deep links and intents. The shell opens the logger and clears it.
  var isLoggerRequested = false
  /// Prefill text for the next logger, from a suggestion's "Log this".
  var loggerPrefill: String?
  var linkError: String?

  var aiConsent: AIConsent {
    didSet { UserDefaults.standard.set(aiConsent.rawValue, forKey: "aiConsent") }
  }
  var isAIConsentGiven: Bool { aiConsent == .allowed }

  let clients: AppClients
  let cache = FileCache()

  init(clients: AppClients) {
    self.clients = clients
    let stored = UserDefaults.standard.string(forKey: "aiConsent") ?? ""
    aiConsent = AIConsent(rawValue: stored) ?? .undecided
  }

  /// Follows auth changes for the life of the app.
  func start() async {
    for await user in clients.account.userChanges() {
      await apply(user)
    }
  }

  private func apply(_ newUser: AccountUser?) async {
    guard let newUser else {
      if user != nil { await clearLocalData() }
      user = nil
      session = .signedOut
      return
    }
    let isNewUser = user?.id != newUser.id
    user = newUser
    guard isNewUser || session == .signedOut || session == .loading else { return }
    session = await needsOnboarding() ? .onboarding : .signedIn
  }

  /// The user's only target has all zeros.
  private func needsOnboarding() async -> Bool {
    var targets: [DailyTarget]? = await cache.read("targets")
    if let fresh = try? await clients.targets.list() {
      targets = fresh
      await cache.write(fresh, for: "targets")
    }
    guard let targets else { return false }
    onboardingTargets = targets
    return targets.count <= 1 && (targets.first?.macros.isAllZero ?? true)
  }

  func finishOnboarding() {
    session = .signedIn
  }

  func handle(_ url: URL) async {
    guard let link = DeepLink(url) else { return }
    switch link {
    case .authCallback(let url):
      do {
        if try await clients.account.handleURL(url) == .passwordRecovery {
          isPasswordRecoveryPresented = true
        }
      } catch {
        linkError = error.localizedDescription
      }
    case .today:
      selectedTab = .today
      selectedDate = today
    case .log:
      selectedTab = .today
      isLoggerRequested = true
    case .suggestions: selectedTab = .suggestions
    case .library: selectedTab = .library
    case .settings: selectedTab = .settings
    }
  }

  func signOut() async {
    try? await clients.account.signOut()
  }

  /// Removes cached data of the previous user.
  private func clearLocalData() async {
    await cache.clear()
    SnapshotStore.clear()
    selectedDate = today
    selectedTab = .today
  }
}
