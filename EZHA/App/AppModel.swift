import EZHAKit
import Foundation
import Observation
import SwiftData

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
    /// Not a screen: the "Log meal" button in the tab bar. Selecting it opens the logger.
    case log
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

  var toast: ToastMessage?
  /// Incremented after each successful log, for the success haptic.
  var logSuccessCount = 0

  let clients: AppClients
  let cache = FileCache()
  let sync: SyncEngine
  let dayStore: DayStore
  let targetsStore: TargetsStore
  let libraryStore: LibraryStore

  init(clients: AppClients, inMemory: Bool = false) {
    self.clients = clients
    let stored = UserDefaults.standard.string(forKey: "aiConsent") ?? ""
    aiConsent = AIConsent(rawValue: stored) ?? .undecided
    let container: ModelContainer
    do {
      container = try LocalStore.makeContainer(inMemory: inMemory)
    } catch {
      // The outbox must not silently lose data; fail loudly instead of running without it.
      fatalError("Could not open the local store: \(error)")
    }
    sync = SyncEngine(container: container, clients: clients)
    dayStore = DayStore(clients: clients, cache: cache, sync: sync)
    targetsStore = TargetsStore(clients: clients, cache: cache)
    libraryStore = LibraryStore(clients: clients, cache: cache)
    dayStore.today = { [weak self] in self?.today ?? .today() }
    targetsStore.today = dayStore.today
    dayStore.onLogged = { [weak self] in self?.logSuccessCount += 1 }
    targetsStore.onChange = { [weak self] in
      guard let self else { return }
      dayStore.invalidate()
      await dayStore.load(selectedDate, force: true)
    }
    OpenLoggerIntent.handler = { [weak self] in self?.openLoggerForToday() }
    sync.onSynced = { [weak self] dates in
      for date in dates { await self?.dayStore.load(date, force: true) }
    }
  }

  func showToast(_ text: String, actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil)
  {
    toast = ToastMessage(text: text, actionTitle: actionTitle, action: action)
  }

  /// Opens the logger for today (widget, control, Siri).
  func openLoggerForToday() {
    refreshToday()
    selectedTab = .today
    selectedDate = today
    isLoggerRequested = true
  }

  /// Moves to the new day when midnight passes while the user is on today.
  func refreshToday() {
    let now = DateKey.today()
    guard now != today else { return }
    let wasOnToday = selectedDate == today
    today = now
    if wasOnToday || selectedDate > now { selectedDate = now }
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
      openLoggerForToday()
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
    await sync.clearAll()
    dayStore.clear()
    targetsStore.clear()
    libraryStore.clear()
    SnapshotStore.clear()
    selectedDate = today
    selectedTab = .today
  }
}
