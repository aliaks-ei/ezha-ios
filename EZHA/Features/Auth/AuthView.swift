import AuthenticationServices
import CryptoKit
import EZHAKit
import SwiftUI

/// Signed-out screen: Sign in with Apple, Google, and email.
struct AuthView: View {
  @Environment(AppModel.self) private var appModel
  @State private var nonce = ""
  @State private var isEmailSheetPresented = false
  @State private var errorMessage: String?
  @State private var isWorking = false

  var body: some View {
    ZStack {
      BrandBackground()
      ScrollView {
        VStack(spacing: 24) {
          Spacer(minLength: 36)
          VStack(spacing: 8) {
            Text("Ezha")
              .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Smarter meal logging with AI estimates you can edit.")
              .font(.body.weight(.medium))
              .multilineTextAlignment(.center)
              .foregroundStyle(.white.opacity(0.92))
          }
          .foregroundStyle(.white)
          .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
          .padding(.horizontal)
          Spacer(minLength: 36)
          VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
              nonce = Self.randomNonce()
              request.requestedScopes = [.email]
              request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
              Task { await completeApple(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(.capsule)

            Button {
              Task { await run { try await appModel.clients.account.signInWithGoogle() } }
            } label: {
              Label("Google", systemImage: "globe")
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .foregroundStyle(.primary)
            .accessibilityLabel("Continue with Google")
            .accessibilityIdentifier("googleSignIn")

            Button {
              isEmailSheetPresented = true
            } label: {
              Label("Email", systemImage: "envelope")
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .foregroundStyle(.primary)

            .accessibilityLabel("Continue with email")
            .accessibilityIdentifier("emailSignIn")

            if let errorMessage {
              Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(Color.danger)
                .multilineTextAlignment(.center)
                .padding(12)
                .background(Color.surface, in: .rect(cornerRadius: 12))
            }
          }
          .disabled(isWorking)
          .padding(.horizontal, 24)
          .padding(.bottom, 24)
          .frame(maxWidth: 500)
        }
        .frame(maxWidth: .infinity)
      }
    }
    .sheet(isPresented: $isEmailSheetPresented) {
      EmailAuthSheet()
    }
  }

  private func completeApple(_ result: Result<ASAuthorization, any Error>) async {
    switch result {
    case .success(let authorization):
      guard
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
        let tokenData = credential.identityToken,
        let token = String(data: tokenData, encoding: .utf8)
      else {
        errorMessage = String(localized: "Sign in with Apple did not return a token.")
        return
      }
      await run { try await appModel.clients.account.signInWithApple(token, nonce) }
    case .failure(let error):
      if (error as? ASAuthorizationError)?.code == .canceled { return }
      errorMessage = error.localizedDescription
    }
  }

  private func run(_ action: () async throws -> Void) async {
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      try await action()
    } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
      return
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  static func randomNonce(length: Int = 32) -> String {
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var generator = SystemRandomNumberGenerator()
    return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
  }

  static func sha256(_ input: String) -> String {
    SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

#Preview {
  AuthView()
    .environment(AppModel(clients: .preview))
}
