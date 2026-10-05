import Foundation
import Supabase

/// The one `SupabaseClient` for the app.
public enum SupabaseProvider {
  public static let client: SupabaseClient = {
    let config = SupabaseConfig.load()
    return SupabaseClient(
      supabaseURL: config.url,
      supabaseKey: config.anonKey,
      options: SupabaseClientOptions(
        auth: .init(
          redirectToURL: URL(string: "ezha://login-callback"),
          flowType: .pkce,
          emitLocalSessionAsInitialSession: true
        )
      )
    )
  }()
}

public struct SupabaseConfig: Sendable {
  public let url: URL
  public let anonKey: String

  /// Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from Info.plist.
  /// Debug builds accept `EZHA_SUPABASE_URL` / `EZHA_SUPABASE_ANON_KEY` from the
  /// environment, so the Simulator can point at local Supabase without a rebuild.
  public static func load(bundle: Bundle = .main) -> SupabaseConfig {
    var urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
    var key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
    #if DEBUG
      let env = ProcessInfo.processInfo.environment
      urlString = env["EZHA_SUPABASE_URL"] ?? urlString
      key = env["EZHA_SUPABASE_ANON_KEY"] ?? key
    #endif
    guard
      let urlString, let url = URL(string: urlString), url.host() != nil,
      let key, !key.isEmpty, !key.hasPrefix("$(")
    else {
      fatalError(
        "SUPABASE_URL or SUPABASE_ANON_KEY is missing from Info.plist. "
          + "Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig and fill in the values."
      )
    }
    return SupabaseConfig(url: url, anonKey: key)
  }
}
