import EZHAKit
import SwiftUI

/// Targets, appearance, AI consent, sync queue, account, and about.
struct SettingsView: View {
  @Environment(AppModel.self) private var appModel
  @AppStorage("appearance") private var appearance = Appearance.system
  @State private var editingTarget: DailyTarget?
  @State private var isNewTargetPresented = false
  @State private var targetError: String?
  @State private var discardItem: PendingItem?
  @State private var isSignOutConfirmPresented = false
  @State private var isDeleteConfirmPresented = false
  @State private var isDeleteFinalPresented = false
  @State private var isDeleting = false
  @State private var accountError: String?

  private var targets: [DailyTarget] { appModel.targetsStore.targets }
  private var pending: [PendingItem] { appModel.sync.items }

  var body: some View {
    @Bindable var appModel = appModel
    NavigationStack {
      Form {
        targetsSection
        Section("Appearance") {
          Picker("Appearance", selection: $appearance) {
            ForEach(Appearance.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
        }
        Section {
          Toggle(
            "Use AI features",
            isOn: Binding(
              get: { appModel.isAIConsentGiven },
              set: { appModel.aiConsent = $0 ? .allowed : .declined }))
        } header: {
          Text("AI features")
        } footer: {
          Text(
            "Photos and descriptions you add are sent to our server and to OpenAI to estimate nutrition and suggest meals. Library and manual logging work without AI."
          )
        }
        if !pending.isEmpty { syncSection }
        accountSection
        aboutSection
      }
      .navigationTitle("Settings")
      .task { await appModel.targetsStore.load() }
      .sheet(item: $editingTarget) { TargetEditorSheet(target: $0) }
      .sheet(isPresented: $isNewTargetPresented) { TargetEditorSheet(target: nil) }
      .confirmationDialog(
        "Discard this change?",
        isPresented: Binding(get: { discardItem != nil }, set: { if !$0 { discardItem = nil } }),
        titleVisibility: .visible, presenting: discardItem
      ) { item in
        Button("Discard", role: .destructive) {
          Task {
            await appModel.sync.remove(id: item.id)
            if let date = item.date { appModel.dayStore.updateSnapshot(date) }
          }
        }
      } message: { item in
        Text(
          item.kind == .logEntry
            ? "This meal was not saved to your account and will be lost."
            : "This entry will not be deleted from your account.")
      }
      .confirmationDialog(
        "Sign out?", isPresented: $isSignOutConfirmPresented, titleVisibility: .visible
      ) {
        Button("Sign out", role: .destructive) { Task { await appModel.signOut() } }
      } message: {
        Text("\(pending.count) changes waiting to sync will be lost.")
      }
      .confirmationDialog(
        "Delete your account?", isPresented: $isDeleteConfirmPresented, titleVisibility: .visible
      ) {
        Button("Delete account", role: .destructive) { isDeleteFinalPresented = true }
      } message: {
        Text("This removes your meals, targets, library, and photos.")
      }
      .alert("Delete account permanently?", isPresented: $isDeleteFinalPresented) {
        Button("Cancel", role: .cancel) {}
        Button("Delete", role: .destructive) { Task { await deleteAccount() } }
      } message: {
        Text("This cannot be undone.")
      }
    }
  }

  // MARK: Sections

  private var targetsSection: some View {
    Section {
      ForEach(targets) { target in
        Button {
          editingTarget = target
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(target.name).foregroundStyle(Color.primary)
            Text(TargetFormat.summary(target))
              .font(.subheadline)
              .fontDesign(.rounded)
              .monospacedDigit()
              .foregroundStyle(Color.secondary)
          }
          .frame(minHeight: 44, alignment: .leading)
        }
        .swipeActions(edge: .trailing) {
          if targets.count > 1 {
            Button("Delete", systemImage: "trash", role: .destructive) {
              Task { await deleteTarget(target) }
            }
          }
        }
      }
      Button("Add target", systemImage: "plus") { isNewTargetPresented = true }
    } header: {
      Text("Daily targets")
    } footer: {
      if let targetError {
        Text(targetError).foregroundStyle(Color.danger)
      } else if targets.count == 1 {
        Text("At least one target is required.")
      }
    }
  }

  private var syncSection: some View {
    Section {
      ForEach(pending) { item in
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 2) {
            Text(title(for: item))
            Text(state(for: item))
              .font(.caption)
              .foregroundStyle(item.lastError == nil ? Color.secondary : Color.danger)
          }
          Spacer()
          Button("Discard") { discardItem = item }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.danger)
        }
        .frame(minHeight: 44)
      }
      Button("Retry now", systemImage: "arrow.clockwise") {
        Task { await appModel.sync.retryNow() }
      }
      .disabled(appModel.sync.isRunning)
    } header: {
      Text("Sync")
    } footer: {
      Text("These changes are saved on this device and sync when you are online.")
    }
  }

  private var accountSection: some View {
    Section {
      LabeledContent("Email", value: appModel.user?.email ?? "—")
      Button("Sign out") {
        if pending.isEmpty {
          Task { await appModel.signOut() }
        } else {
          isSignOutConfirmPresented = true
        }
      }
      Button(role: .destructive) {
        isDeleteConfirmPresented = true
      } label: {
        HStack {
          Text("Delete account")
          if isDeleting {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(isDeleting)
    } header: {
      Text("Account")
    } footer: {
      if let accountError { Text(accountError).foregroundStyle(Color.danger) }
    }
  }

  private var aboutSection: some View {
    Section("About") {
      LabeledContent("Version", value: Self.version)
      if let url = Self.privacyPolicyURL {
        Link("Privacy policy", destination: url)
      }
    }
  }

  // MARK: Helpers

  private func title(for item: PendingItem) -> String {
    switch item.kind {
    case .logEntry:
      let text = item.logPayload?.entry.inputText ?? String(localized: "Meal")
      return String(localized: "Log \(text)")
    case .deleteEntry:
      return String(localized: "Delete an entry")
    }
  }

  private func state(for item: PendingItem) -> String {
    if let error = item.lastError { return error }
    if item.attempts == 0 { return String(localized: "Waiting to sync") }
    return String(
      localized:
        "Retrying \(item.nextAttemptAt.formatted(.relative(presentation: .named))) · attempt \(item.attempts)"
    )
  }

  private func deleteTarget(_ target: DailyTarget) async {
    targetError = nil
    do {
      try await appModel.targetsStore.delete(target)
    } catch {
      targetError = OnlineError.message(for: error)
    }
  }

  private func deleteAccount() async {
    isDeleting = true
    accountError = nil
    defer { isDeleting = false }
    do {
      try await appModel.clients.account.deleteAccount()
      await appModel.signOut()
    } catch {
      accountError = OnlineError.message(for: error)
    }
  }

  static var version: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = info?["CFBundleVersion"] as? String ?? "1"
    return "\(short) (\(build))"
  }

  /// `PRIVACY_POLICY_URL` from Info.plist (set in Config/Shared.xcconfig). Hidden when empty.
  static var privacyPolicyURL: URL? {
    (Bundle.main.object(forInfoDictionaryKey: "PRIVACY_POLICY_URL") as? String)
      .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : URL(string: $0) }
  }
}

#Preview {
  SettingsView()
    .environment(AppModel(clients: .preview, inMemory: true))
}
