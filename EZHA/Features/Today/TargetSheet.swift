import EZHAKit
import SwiftUI

/// Pick the target for one day. Confirms when the day has entries.
struct TargetSheet: View {
  var date: DateKey
  var bundle: DayBundle
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var pending: DailyTarget?
  @State private var isEditorPresented = false
  @State private var errorMessage: String?
  @State private var isSaving = false

  private var targets: [DailyTarget] {
    appModel.targetsStore.targets.isEmpty ? bundle.targets : appModel.targetsStore.targets
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(targets) { target in
            Button {
              select(target)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(target.name).font(.body.weight(.medium))
                  Text(TargetFormat.summary(target))
                    .font(.subheadline)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if target.id == bundle.target?.id {
                  Image(systemName: "checkmark")
                    .foregroundStyle(Color.brandPrimary)
                    .accessibilityLabel("Selected")
                }
              }
              .frame(minHeight: 44)
              .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
          }
        } footer: {
          if let errorMessage {
            Text(errorMessage).foregroundStyle(Color.danger)
          }
        }
        Section {
          Button("Add new target", systemImage: "plus") { isEditorPresented = true }
        }
      }
      .navigationTitle(date == appModel.today ? "Today's target" : "Day target")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") { dismiss() }
        }
      }
      .confirmationDialog(
        "Change to \(pending?.name ?? "")?",
        isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
        titleVisibility: .visible,
        presenting: pending
      ) { target in
        Button("Change to \(target.name)") { Task { await apply(target) } }
        Button("Cancel", role: .cancel) {}
      } message: { _ in
        Text("Your logged meals stay the same. Only this day's goals and remaining macros update.")
      }
      .sheet(isPresented: $isEditorPresented) {
        TargetEditorSheet(target: nil)
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func select(_ target: DailyTarget) {
    guard target.id != bundle.target?.id else {
      dismiss()
      return
    }
    if bundle.entries.isEmpty {
      Task { await apply(target) }
    } else {
      pending = target
    }
  }

  private func apply(_ target: DailyTarget) async {
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    do {
      try await appModel.dayStore.setTarget(target.id, for: date)
      dismiss()
    } catch {
      errorMessage = OnlineError.message(for: error)
    }
  }
}

enum TargetFormat {
  /// "2,100 kcal · P140 · C220 · F70"
  static func summary(_ target: DailyTarget) -> String {
    let n = { (value: Double) in value.formatted(.number.precision(.fractionLength(0))) }
    return String(
      localized:
        "\(n(target.caloriesTarget)) kcal · P\(n(target.proteinTarget)) · C\(n(target.carbsTarget)) · F\(n(target.fatTarget))"
    )
  }
}

/// Errors for online-only changes.
enum OnlineError {
  static func message(for error: any Error) -> String {
    isNetworkError(error)
      ? String(localized: "You're offline. This change needs a connection.")
      : error.localizedDescription
  }
}
