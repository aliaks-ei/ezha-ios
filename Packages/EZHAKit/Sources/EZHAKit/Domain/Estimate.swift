import Foundation

/// An `ai-estimate` result. Port of `toEstimate` in `src/services/ai-analysis-service.ts`.
public struct Estimate: Codable, Sendable, Hashable {
  public enum NutritionBasis: String, Codable, Sendable {
    case per100g = "per_100g"
    case perPortion = "per_portion"
  }

  public struct Review: Codable, Sendable, Hashable {
    public var question: String
    public var kind: String
    public var itemIndex: Int

    public init(question: String, kind: String, itemIndex: Int) {
      self.question = question
      self.kind = kind
      self.itemIndex = itemIndex
    }

    enum CodingKeys: String, CodingKey {
      case question, kind
      case itemIndex = "item_index"
    }
  }

  public struct Item: Codable, Sendable, Hashable {
    public var name: String
    public var grams: Double
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var confidence: Double?
    public var notes: String?
    public var nutritionSource: String?
    public var nutritionSourceId: String?
    public var portionEstimated: Bool?

    public init(
      name: String, grams: Double, macros: MacroTotals, confidence: Double? = nil,
      notes: String? = nil, nutritionSource: String? = nil, nutritionSourceId: String? = nil,
      portionEstimated: Bool? = nil
    ) {
      self.name = name
      self.grams = grams
      self.calories = macros.calories
      self.protein = macros.protein
      self.carbs = macros.carbs
      self.fat = macros.fat
      self.confidence = confidence
      self.notes = notes
      self.nutritionSource = nutritionSource
      self.nutritionSourceId = nutritionSourceId
      self.portionEstimated = portionEstimated
    }

    public var macros: MacroTotals {
      MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    enum CodingKeys: String, CodingKey {
      case name, grams, calories, protein, carbs, fat, confidence, notes
      case nutritionSource = "nutrition_source"
      case nutritionSourceId = "nutrition_source_id"
      case portionEstimated = "portion_estimated"
    }
  }

  public var totals: MacroTotals
  public var confidence: Double?
  public var source: String
  public var foodName: String?
  public var notes: String
  public var items: [Item]
  public var nutritionBasis: NutritionBasis?
  public var review: Review?

  public init(
    totals: MacroTotals, confidence: Double? = nil, source: String, foodName: String? = nil,
    notes: String = "", items: [Item] = [], nutritionBasis: NutritionBasis? = nil,
    review: Review? = nil
  ) {
    self.totals = totals
    self.confidence = confidence
    self.source = source
    self.foodName = foodName
    self.notes = notes
    self.items = items
    self.nutritionBasis = nutritionBasis
    self.review = review
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
    let values = [totals.calories, totals.protein, totals.carbs, totals.fat]
    guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
      throw AIError.message("Analysis returned invalid nutrition values.")
    }
    if raw.nutritionBasis != nil && (raw.items?.isEmpty ?? true) {
      throw AIError.message("Analysis returned no food items.")
    }
    if source == "label_photo" && raw.nutritionBasis != .per100g {
      throw AIError.message(
        "Label analysis needs the updated backend. Enter values per 100 g manually.")
    }
    for item in raw.items ?? [] {
      guard !item.name.trimmed.isEmpty, item.grams.isFinite, item.grams > 0,
        item.grams <= LogItemMath.maxGrams,
        [item.calories, item.protein, item.carbs, item.fat].allSatisfy({ $0.isFinite && $0 >= 0 })
      else { throw AIError.message("Analysis returned invalid food items.") }
    }
    if let review = raw.review {
      guard ["portion", "ingredient", "identity"].contains(review.kind),
        !review.question.trimmed.isEmpty, review.itemIndex >= 0,
        review.itemIndex < (raw.items?.count ?? 0)
      else { throw AIError.message("Analysis returned an invalid review question.") }
    }
    return Estimate(
      totals: totals, confidence: raw.confidence, source: source, foodName: raw.foodName,
      notes: notes, items: raw.items ?? [], nutritionBasis: raw.nutritionBasis, review: raw.review)
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
    var nutritionBasis: NutritionBasis?
    var review: Review?

    enum CodingKeys: String, CodingKey {
      case totals, calories, protein, carbs, fat, confidence, source, notes, items, error
      case foodName = "food_name"
      case nutritionBasis = "nutrition_basis"
      case review
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
  case item(index: Int, item: Estimate.Item)
  case reset
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
    case "item":
      struct Preview: Decodable {
        var index: Int
        var item: Estimate.Item
      }
      guard let preview = try? JSONDecoder().decode(Preview.self, from: data),
        (0..<20).contains(preview.index), preview.item.grams.isFinite, preview.item.grams > 0,
        !preview.item.name.trimmed.isEmpty,
        [preview.item.calories, preview.item.protein, preview.item.carbs, preview.item.fat]
          .allSatisfy({ $0.isFinite && $0 >= 0 })
      else { return nil }
      return .item(index: preview.index, item: preview.item)
    case "reset":
      return .reset
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
