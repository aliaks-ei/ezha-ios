import Foundation
import Supabase

public struct AccountUser: Sendable, Hashable {
  public var id: UUID
  public var email: String?

  public init(id: UUID, email: String?) {
    self.id = id
    self.email = email
  }
}

/// What a deep link did.
public enum AuthLinkResult: Sendable, Equatable {
  case signedIn
  case passwordRecovery
}

/// Sign-in methods, sign out, password reset, account deletion.
public struct AccountClient: Sendable {
  /// Emits the signed-in user, or nil when signed out. Starts with the stored session.
  public var userChanges: @Sendable () -> AsyncStream<AccountUser?>
  public var signInWithApple: @Sendable (_ idToken: String, _ nonce: String) async throws -> Void
  public var signInWithGoogle: @Sendable () async throws -> Void
  public var signIn: @Sendable (_ email: String, _ password: String) async throws -> Void
  /// Returns true when the account needs email confirmation before sign-in.
  public var signUp: @Sendable (_ email: String, _ password: String) async throws -> Bool
  public var resetPassword: @Sendable (_ email: String) async throws -> Void
  public var updatePassword: @Sendable (_ password: String) async throws -> Void
  public var handleURL: @Sendable (URL) async throws -> AuthLinkResult
  public var signOut: @Sendable () async throws -> Void
  public var deleteAccount: @Sendable () async throws -> Void

  public init(
    userChanges: @escaping @Sendable () -> AsyncStream<AccountUser?>,
    signInWithApple: @escaping @Sendable (String, String) async throws -> Void,
    signInWithGoogle: @escaping @Sendable () async throws -> Void,
    signIn: @escaping @Sendable (String, String) async throws -> Void,
    signUp: @escaping @Sendable (String, String) async throws -> Bool,
    resetPassword: @escaping @Sendable (String) async throws -> Void,
    updatePassword: @escaping @Sendable (String) async throws -> Void,
    handleURL: @escaping @Sendable (URL) async throws -> AuthLinkResult,
    signOut: @escaping @Sendable () async throws -> Void,
    deleteAccount: @escaping @Sendable () async throws -> Void
  ) {
    self.userChanges = userChanges
    self.signInWithApple = signInWithApple
    self.signInWithGoogle = signInWithGoogle
    self.signIn = signIn
    self.signUp = signUp
    self.resetPassword = resetPassword
    self.updatePassword = updatePassword
    self.handleURL = handleURL
    self.signOut = signOut
    self.deleteAccount = deleteAccount
  }
}

extension AccountClient {
  public static let loginCallback = URL(string: "ezha://login-callback")!
  public static let resetPasswordCallback = URL(string: "ezha://reset-password")!

  public static let live = AccountClient(
    userChanges: {
      AsyncStream { continuation in
        let task = Task {
          for await (event, session) in SupabaseProvider.client.auth.authStateChanges {
            // With emitLocalSessionAsInitialSession, the stored session may be expired.
            // Supabase refreshes it in the background; a failed refresh emits signedOut.
            if event == .passwordRecovery { continue }
            continuation.yield(session.map { AccountUser(id: $0.user.id, email: $0.user.email) })
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    },
    signInWithApple: { idToken, nonce in
      _ = try await SupabaseProvider.client.auth.signInWithIdToken(
        credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
    },
    signInWithGoogle: {
      _ = try await SupabaseProvider.client.auth.signInWithOAuth(
        provider: .google, redirectTo: loginCallback)
    },
    signIn: { email, password in
      _ = try await SupabaseProvider.client.auth.signIn(email: email, password: password)
    },
    signUp: { email, password in
      let response = try await SupabaseProvider.client.auth.signUp(
        email: email, password: password, redirectTo: loginCallback)
      return response.session == nil
    },
    resetPassword: { email in
      try await SupabaseProvider.client.auth.resetPasswordForEmail(
        email, redirectTo: resetPasswordCallback)
    },
    updatePassword: { password in
      _ = try await SupabaseProvider.client.auth.update(user: UserAttributes(password: password))
    },
    handleURL: { url in
      _ = try await SupabaseProvider.client.auth.session(from: url)
      return url.host() == resetPasswordCallback.host() ? .passwordRecovery : .signedIn
    },
    signOut: {
      try await SupabaseProvider.client.auth.signOut(scope: .local)
    },
    deleteAccount: {
      let (bytes, response) = try await FunctionCaller.send(
        "delete-account", body: [String: String](), stream: false)
      guard (200..<300).contains(response.statusCode) else {
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        throw FunctionCaller.error(from: data, status: response.statusCode)
      }
      try? await SupabaseProvider.client.auth.signOut(scope: .local)
    }
  )
}
