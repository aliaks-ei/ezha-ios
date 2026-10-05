import EZHAKit
import SwiftUI

/// Create or edit a daily target. Name required, four numeric fields.
struct TargetEditorSheet: View {
  var target: DailyTarget?
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var macros: MacroFieldsModel
  @State private var errorMessage: String?
  @State private var isSaving = false

  init(target: DailyTarget?) {
    self.target = target
    _name = State(initialValue: target?.name ?? "")
    _macros = State(
      initialValue: target.map { MacroFieldsModel(values: $0.macros) } ?? MacroFieldsModel())
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty && macros.values != nil && !isSaving
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
            .textInputAutocapitalization(.words)
        }
        Section {
          MacroFields(model: $macros)
        } footer: {
          Text("Macros add up to \(Macros.format(macros.macroCalories, maxFractionDigits: 0)) kcal")
        }
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(Color.danger) }
        }
      }
      .navigationTitle(target == nil ? "New target" : "Edit target")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }
            .disabled(!canSave)
        }
      }
    }
    .presentationDetents([.large])
  }

  private func save() async {
    guard let values = macros.values else { return }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    do {
      try await appModel.targetsStore.save(
        id: target?.id, name: name.trimmingCharacters(in: .whitespaces), macros: values)
      dismiss()
    } catch {
      errorMessage = OnlineError.message(for: error)
    }
  }
}
