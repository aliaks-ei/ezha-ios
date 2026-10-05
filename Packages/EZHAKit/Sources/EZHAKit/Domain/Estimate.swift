import Foundation

/// An `ai-estimate` result. Port of `toEstimate` in `src/services/ai-analysis-service.ts`.
public struct Estimate: Codable, Sendable, Hashable {
  public struct Item: Codable, Sendable, Hashable {
    public var name: String
    public var grams: Double
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var confidence: Double?
    public var notes: String?

    public init(
      name: String, grams: Double, macros: MacroTotals, confidence: Double? = nil,
      notes: String? = nil
    ) {
      self.name = name
      self.grams = grams
      self.calories = macros.calories
      self.protein = macros.protein
      self.carbs = macros.carbs
      self.fat = macros.fat
      self.confidence = confidence
      self.notes = notes
    }

    public var macros: MacroTotals {
      MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
  }

  public var totals: MacroTotals
  public var confidence: Double?
  public var source: String
  public var foodName: String?
  public var notes: String
  public var items: [Item]

  public init(
    totals: MacroTotals, confidence: Double? = nil, source: String, foodName: String? = nil,
    notes: String = "", items: [Item] = []
  ) {
    self.totals = totals
    self.confidence = confidence
    self.source = source
    self.foodName = foodName
    self.notes = notes
    self.items = items
  }

  /// Parses the JSON body. An `error` field fails even with HTTP 200.
  public static func parse(_ data: Data) throws(AIError) -> Estimate {
    let raw: RawEstimate
    do {
      raw = try JSONDecoder().decode(RawEstimate.self, from: data)
    } catch {
      throw AIError.message("Analysis returned an invalid response.")
    }
    if let error = raw.error, !error.isEmpty { throw AIError.message(error) }
    let totals =
      raw.totals
      ?? {
        guard let c = raw.calories, let p = raw.protein, let cb = raw.carbs, let f = raw.fat
        else { return nil }
        return MacroTotals(calories: c, protein: p, carbs: cb, fat: f)
      }()
    guard let totals, let source = raw.source, !source.isEmpty, let notes = raw.notes else {
      throw AIError.message("Analysis returned an invalid response.")
    }
    return Estimate(
      totals: totals, confidence: raw.confidence, source: source, foodName: raw.foodName,
      notes: notes, items: raw.items ?? [])
  }

  private struct RawEstimate: Decodable {
    var totals: MacroTotals?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var confidence: Double?
    var source: String?
    var foodName: String?
    var notes: String?
    var items: [Item]?
    var error: String?

    enum CodingKeys: String, CodingKey {
      case totals, calories, protein, carbs, fat, confidence, source, notes, items, error
      case foodName = "food_name"
    }
  }
}

public enum AIError: Error, Sendable, Equatable, LocalizedError {
  case message(String)
  case sessionExpired

  public var errorDescription: String? {
    switch self {
    case .message(let text): text
    case .sessionExpired: "Your session expired. Please log in again."
    }
  }
}

/// Events from the streaming `ai-estimate` call.
public enum EstimateEvent: Sendable, Equatable {
  case uploading
  case status(String)
  case delta
  case result(Estimate)
}

/// Server-sent events parser. Blocks are split by a blank line. Feed it raw text in any chunks.
public struct SSEParser: Sendable {
  public struct Message: Sendable, Equatable {
    public var event: String
    public var data: String
  }

  private var buffer = ""
  private var event: String?
  private var dataLines: [String] = []

  public init() {}

  /// Returns the messages completed by this chunk.
  public mutating func feed(_ chunk: String) -> [Message] {
    buffer += chunk
    var messages: [Message] = []
    while let newline = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
      let line = String(buffer[..<newline])
      buffer.removeSubrange(...newline)
      if let message = process(line) { messages.append(message) }
    }
    return messages
  }

  /// Call at the end of the stream to flush a block without a trailing blank line.
  public mutating func finish() -> [Message] {
    var messages = feed("\n")
    if let message = process("") { messages.append(message) }
    return messages
  }

  private mutating func process(_ line: String) -> Message? {
    if line.isEmpty {
      defer {
        event = nil
        dataLines = []
      }
      guard let event, !dataLines.isEmpty else { return nil }
      return Message(event: event, data: dataLines.joined(separator: "\n"))
    }
    if line.hasPrefix("event:") {
      event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
    } else if line.hasPrefix("data:") {
      dataLines.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
    }
    return nil
  }

  /// Maps one message to an event. Unknown events return nil.
  public static func estimateEvent(from message: Message) throws(AIError) -> EstimateEvent? {
    let data = Data(message.data.utf8)
    switch message.event {
    case "status":
      let stage = (try? JSONDecoder().decode([String: String].self, from: data))?["stage"]
      return stage.map(EstimateEvent.status)
    case "delta":
      return .delta
    case "result":
      return .result(try Estimate.parse(data))
    case "error":
      let error = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
      throw AIError.message(error ?? "Analysis failed.")
    default:
      return nil
    }
  }
}

/// One `ai-suggestions` result.
public struct MealSuggestion: Codable, Sendable, Hashable, Identifiable {
  public var id = UUID()
  public var title: String
  public var description: String
  public var calories: Double
  public var protein: Double
  public var carbs: Double
  public var fat: Double
  public var notes: String?

  public var macros: MacroTotals {
    MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat)
  }

  enum CodingKeys: String, CodingKey {
    case title, description, calories, protein, carbs, fat, notes
  }

  public init(
    title: String, description: String, macros: MacroTotals, notes: String? = nil
  ) {
    self.title = title
    self.description = description
    self.calories = macros.calories
    self.protein = macros.protein
    self.carbs = macros.carbs
    self.fat = macros.fat
    self.notes = notes
  }

  /// Parses `{ suggestions, error }`. An empty or missing list is an error.
  public static func parse(_ data: Data) throws(AIError) -> [MealSuggestion] {
    struct Raw: Decodable {
      var suggestions: [MealSuggestion]?
      var error: String?
    }
    guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else {
      throw AIError.message("Suggestions returned an invalid response.")
    }
    if let error = raw.error, !error.isEmpty { throw AIError.message(error) }
    guard let list = raw.suggestions, !list.isEmpty else {
      throw AIError.message("Suggestions returned an invalid response.")
    }
    return Array(list.prefix(3))
  }
}
