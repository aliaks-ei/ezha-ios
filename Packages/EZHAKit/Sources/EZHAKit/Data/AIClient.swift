import Foundation
import Supabase

public struct EstimateRequest: Codable, Sendable, Hashable {
  public struct Item: Codable, Sendable, Hashable {
    public var name: String
    /// Amount in `unit`.
    public var grams: Double
    public var unit: AmountUnit
    public init(name: String, grams: Double, unit: AmountUnit = .g) {
      self.name = name
      self.grams = grams
      self.unit = unit
    }
  }

  public var text: String?
  public var items: [Item]?
  public var imagePath: String?
  /// Restaurant meals: the photo of what is left. `imagePath` is the photo of what was served.
  public var leftoverImagePath: String?
  /// `text`, `food_photo`, `label_photo`, or `restaurant_photos`.
  public var inputType: String
  public var stream = true

  public init(
    text: String?, items: [Item]?, imagePath: String?, leftoverImagePath: String? = nil,
    inputType: String
  ) {
    self.text = text?.trimmed.nonEmpty
    self.items = items.flatMap { $0.isEmpty ? nil : $0 }
    self.imagePath = imagePath
    self.leftoverImagePath = leftoverImagePath
    self.inputType = inputType
  }
}

public struct SuggestionsRequest: Codable, Sendable, Hashable {
  public var remaining: MacroTotals
  public var mealType: String
  public var maxPrepMinutes: Int
  public var count = SuggestionRules.count
  public var ingredientNotes: String?
  public var variationNote: String?
  public var units = SuggestionRules.units
  /// Recent suggestion titles the model should not repeat.
  public var avoidTitles: [String]?
  /// The user's local hour (0–23), so ideas fit breakfast, lunch, or dinner.
  /// Nil when planning a day other than today.
  public var localHour: Int?

  public init(
    remaining: MacroTotals, mealType: SuggestionRules.MealType, maxPrepMinutes: Int,
    ingredientNotes: String?, variationNote: String?, avoidTitles: [String] = [],
    localHour: Int? = nil
  ) {
    self.remaining = remaining
    self.mealType = mealType.rawValue
    self.maxPrepMinutes = maxPrepMinutes
    self.ingredientNotes = ingredientNotes?.trimmed.nonEmpty
    self.variationNote = variationNote
    self.avoidTitles = avoidTitles.isEmpty ? nil : avoidTitles
    self.localHour = localHour
  }

  enum CodingKeys: String, CodingKey {
    case remaining
    case mealType = "meal_type"
    case maxPrepMinutes = "max_prep_minutes"
    case count
    case ingredientNotes = "ingredient_notes"
    case variationNote = "variation_note"
    case units
    case avoidTitles = "avoid_titles"
    case localHour = "local_hour"
  }
}

/// Dishes from restaurant menu photos that fit the remaining macros (`ai-menu-suggestions`).
public struct MenuSuggestionsRequest: Codable, Sendable, Hashable {
  public var remaining: MacroTotals
  public var mealType: String
  public var preferences: String?
  public var variationNote: String?
  /// Base64 JPEGs, one per menu page.
  public var images: [String]

  public init(
    remaining: MacroTotals, mealType: SuggestionRules.MealType, preferences: String?,
    variationNote: String?, photos: [Data]
  ) {
    self.remaining = remaining
    self.mealType = mealType.rawValue
    self.preferences = preferences?.trimmed.nonEmpty
    self.variationNote = variationNote
    self.images = photos.map { $0.base64EncodedString() }
  }

  enum CodingKeys: String, CodingKey {
    case remaining
    case mealType = "meal_type"
    case preferences
    case variationNote = "variation_note"
    case images
  }
}

/// Edge functions `ai-estimate` (streaming), `ai-suggestions`, and `ai-menu-suggestions`.
public struct AIClient: Sendable {
  public var estimateStream:
    @Sendable (EstimateRequest) -> AsyncThrowingStream<EstimateEvent, any Error>
  public var suggestions: @Sendable (SuggestionsRequest) async throws -> [MealSuggestion]
  public var menuSuggestions: @Sendable (MenuSuggestionsRequest) async throws -> [MealSuggestion]

  public init(
    estimateStream:
      @escaping @Sendable (EstimateRequest) -> AsyncThrowingStream<
        EstimateEvent, any Error
      >,
    suggestions: @escaping @Sendable (SuggestionsRequest) async throws -> [MealSuggestion],
    menuSuggestions:
      @escaping @Sendable (MenuSuggestionsRequest) async throws -> [MealSuggestion]
  ) {
    self.estimateStream = estimateStream
    self.suggestions = suggestions
    self.menuSuggestions = menuSuggestions
  }
}

extension AIClient {
  public static let live = AIClient(
    estimateStream: { request in
      AsyncThrowingStream { continuation in
        let task = Task {
          do {
            let (bytes, response) = try await FunctionCaller.send(
              "ai-estimate", body: request, stream: true)
            guard (200..<300).contains(response.statusCode) else {
              var data = Data()
              for try await byte in bytes { data.append(byte) }
              throw FunctionCaller.error(from: data, status: response.statusCode)
            }
            var parser = SSEParser()
            var line = Data()
            func handle(_ messages: [SSEParser.Message]) throws {
              for message in messages {
                if let event = try SSEParser.estimateEvent(from: message) {
                  continuation.yield(event)
                }
              }
            }
            for try await byte in bytes {
              line.append(byte)
              if byte == UInt8(ascii: "\n") {
                try handle(parser.feed(String(decoding: line, as: UTF8.self)))
                line.removeAll(keepingCapacity: true)
              }
            }
            if !line.isEmpty { try handle(parser.feed(String(decoding: line, as: UTF8.self))) }
            try handle(parser.finish())
            continuation.finish()
          } catch {
            continuation.finish(throwing: error)
          }
        }
        continuation.onTermination = { _ in task.cancel() }
      }
    },
    suggestions: { request in
      let (bytes, response) = try await FunctionCaller.send(
        "ai-suggestions", body: request, stream: false)
      var data = Data()
      for try await byte in bytes { data.append(byte) }
      guard (200..<300).contains(response.statusCode) else {
        throw FunctionCaller.error(from: data, status: response.statusCode)
      }
      return try MealSuggestion.parse(data)
    },
    menuSuggestions: { request in
      let (bytes, response) = try await FunctionCaller.send(
        "ai-menu-suggestions", body: request, stream: false)
      var data = Data()
      for try await byte in bytes { data.append(byte) }
      guard (200..<300).contains(response.statusCode) else {
        throw FunctionCaller.error(from: data, status: response.statusCode)
      }
      return try MealSuggestion.parse(data, limit: SuggestionRules.menuCount)
    }
  )
}

/// Calls an edge function with the session token. On HTTP 401 it refreshes the session once
/// and retries once. If the refresh fails, it signs out and throws `AIError.sessionExpired`.
enum FunctionCaller {
  static func send(_ name: String, body: some Encodable & Sendable, stream: Bool) async throws
    -> (URLSession.AsyncBytes, HTTPURLResponse)
  {
    let client = SupabaseProvider.client
    let token = try await client.auth.session.accessToken
    let first = try await request(name, body: body, stream: stream, token: token)
    guard first.1.statusCode == 401 else { return first }
    let refreshed: Session
    do {
      refreshed = try await client.auth.refreshSession()
    } catch {
      try? await client.auth.signOut(scope: .local)
      throw AIError.sessionExpired
    }
    return try await request(name, body: body, stream: stream, token: refreshed.accessToken)
  }

  static func request(_ name: String, body: some Encodable, stream: Bool, token: String)
    async throws -> (URLSession.AsyncBytes, HTTPURLResponse)
  {
    let config = SupabaseConfig.load()
    var request = URLRequest(url: config.url.appending(path: "functions/v1/\(name)"))
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(
      stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
    request.httpBody = try JSONEncoder().encode(body)
    let (bytes, response) = try await URLSession.shared.bytes(for: request)
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return (bytes, http)
  }

  static func error(from data: Data, status: Int) -> AIError {
    let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
    return .message(message ?? "The request failed with status \(status).")
  }
}
