import EZHAKit
import SwiftUI

/// Opened by the password recovery link.
struct NewPasswordSheet: View {
  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var password = ""
  @State private var errorMessage: String?
  @State private var isWorking = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField("New password", text: $password)
            .textContentType(.newPassword)
        } footer: {
          if let errorMessage {
            Text(errorMessage).foregroundStyle(Color.danger)
          } else {
            Text("Use at least 6 characters.")
          }
        }
      }
      .navigationTitle("Set new password")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }
            .disabled(password.count < 6 || isWorking)
        }
      }
    }
    .presentationDetents([.medium])
  }

  private func save() async {
    isWorking = true
    defer { isWorking = false }
    do {
      try await appModel.clients.account.updatePassword(password)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
