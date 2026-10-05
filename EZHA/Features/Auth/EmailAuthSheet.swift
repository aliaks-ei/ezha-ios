import EZHAKit
import SwiftUI

/// Email sign in and sign up, with "Forgot password?".
struct EmailAuthSheet: View {
  enum Mode: Hashable {
    case signIn
    case signUp
  }

  @Environment(AppModel.self) private var appModel
  @Environment(\.dismiss) private var dismiss
  @State private var mode = Mode.signIn
  @State private var email = ""
  @State private var password = ""
  @State private var errorMessage: String?
  @State private var infoMessage: String?
  @State private var isWorking = false
  @FocusState private var focused: Field?

  enum Field {
    case email
    case password
  }

  private var canSubmit: Bool {
    email.contains("@") && password.count >= 6 && !isWorking
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Mode", selection: $mode) {
            Text("Sign in").tag(Mode.signIn)
            Text("Create account").tag(Mode.signUp)
          }
          .pickerStyle(.segmented)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }
        Section {
          TextField("Email", text: $email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused, equals: .email)
            .submitLabel(.next)
            .onSubmit { focused = .password }
          SecureField("Password", text: $password)
            .textContentType(mode == .signIn ? .password : .newPassword)
            .focused($focused, equals: .password)
            .submitLabel(.go)
            .onSubmit { Task { await submit() } }
        } footer: {
          VStack(alignment: .leading, spacing: 8) {
            if mode == .signUp {
              Text("Use at least 6 characters.")
            }
            if let errorMessage {
              Text(errorMessage).foregroundStyle(Color.danger)
            }
            if let infoMessage {
              Text(infoMessage)
            }
          }
        }
        Section {
          Button {
            Task { await submit() }
          } label: {
            HStack {
              Spacer()
              if isWorking {
                ProgressView()
              } else {
                Text(mode == .signIn ? "Sign in" : "Create account").bold()
              }
              Spacer()
            }
          }
          .disabled(!canSubmit)
          .accessibilityIdentifier("emailSubmit")
          if mode == .signIn {
            Button("Forgot password?") {
              Task { await resetPassword() }
            }
            .disabled(isWorking)
          }
        }
      }
      .navigationTitle(mode == .signIn ? "Sign in" : "Create account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") { dismiss() }
        }
      }
      .onChange(of: mode) {
        errorMessage = nil
        infoMessage = nil
      }
      .onAppear { focused = .email }
    }
    .presentationDetents([.medium, .large])
  }

  private func submit() async {
    guard canSubmit else { return }
    isWorking = true
    errorMessage = nil
    infoMessage = nil
    defer { isWorking = false }
    let email = email.trimmingCharacters(in: .whitespaces)
    do {
      switch mode {
      case .signIn:
        try await appModel.clients.account.signIn(email, password)
        dismiss()
      case .signUp:
        if try await appModel.clients.account.signUp(email, password) {
          infoMessage = String(localized: "Check your email to confirm your account, then sign in.")
          mode = .signIn
        } else {
          dismiss()
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func resetPassword() async {
    let email = email.trimmingCharacters(in: .whitespaces)
    guard email.contains("@") else {
      errorMessage = String(localized: "Enter your email first.")
      return
    }
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      try await appModel.clients.account.resetPassword(email)
      infoMessage = String(localized: "If an account exists, a reset link is on its way.")
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

#Preview {
  EmailAuthSheet()
    .environment(AppModel(clients: .preview))
}
