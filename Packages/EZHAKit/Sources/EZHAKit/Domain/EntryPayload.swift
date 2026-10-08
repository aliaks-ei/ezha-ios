import Foundation

/// The sources used to build a meal.
public struct UsedSources: Codable, Sendable, Hashable {
  public var usedPhoto: Bool
  public var usedText: Bool
  public var usedLibrary: Bool

  public init(usedPhoto: Bool = false, usedText: Bool = false, usedLibrary: Bool = false) {
    self.usedPhoto = usedPhoto
    self.usedText = usedText
    self.usedLibrary = usedLibrary
  }
}

/// What `log_food_entry` receives. Also the outbox payload for `logEntry`.
public struct LogPayload: Codable, Sendable, Hashable {
  public var entry: FoodEntry
  public var items: [FoodEntryItem]
  public var usedFoodIds: [UUID]
  /// Local time of day, counted per used food. Nil in outbox payloads saved before it existed.
  public var timeSlot: TimeSlot?

  public init(
    entry: FoodEntry, items: [FoodEntryItem], usedFoodIds: [UUID], timeSlot: TimeSlot? = nil
  ) {
    self.entry = entry
    self.items = items
    self.usedFoodIds = usedFoodIds
    self.timeSlot = timeSlot
  }

  enum CodingKeys: String, CodingKey {
    case entry, items
    case usedFoodIds = "used_food_ids"
    case timeSlot = "time_slot"
  }
}

/// Port of `buildFoodEntryPayload` and `resolveFoodEntryInput`.
public enum EntryPayload {
  public static let notes = "Logged from combined meal sources"

  public static func resolveInput(_ sources: UsedSources, isLabelPhoto: Bool) -> (
    inputType: InputType, aiSource: AISource
  ) {
    let photoSource: AISource = isLabelPhoto ? .labelPhoto : .foodPhoto
    if sources.usedPhoto && sources.usedText { return (.photoText, photoSource) }
    if sources.usedPhoto { return (.photo, photoSource) }
    if sources.usedText { return (.text, .text) }
    if sources.usedLibrary { return (.text, .library) }
    return (.text, .unknown)
  }

  /// `inputType` for the `ai-estimate` request.
  public static func analyzeInputType(hasPhoto: Bool, isLabelPhoto: Bool) -> String {
    hasPhoto ? (isLabelPhoto ? "label_photo" : "food_photo") : "text"
  }

  /// Rows skip items with no name, grams ≤ 0, or missing nutrition.
  public static func entryItems(entryId: UUID, from items: [LogItem]) -> [FoodEntryItem] {
    items.compactMap { item in
      let name = item.name.trimmed
      guard let grams = LogItemMath.validGrams(item.gramsText), !name.isEmpty,
        !item.isNutritionMissing
      else { return nil }
      return FoodEntryItem(
        id: UUID(), entryId: entryId, name: name, grams: grams, macros: LogItemMath.macros(item),
        aiConfidence: item.aiConfidence, aiNotes: item.aiNotes)
    }
  }

  /// Item names joined with ", ", or "Meal".
  public static func inputText(_ rows: [FoodEntryItem]) -> String {
    let names = rows.map(\.name.trimmed).filter { !$0.isEmpty }
    return names.isEmpty ? "Meal" : names.joined(separator: ", ")
  }

  public static func build(
    entryId: UUID = UUID(), date: DateKey, imagePath: String?, items: [LogItem],
    sources: UsedSources, isLabelPhoto: Bool, inputTextOverride: String? = nil,
    extraUsedFoodIds: [UUID] = [], createdAt: Date = .now
  ) -> LogPayload {
    let rows = entryItems(entryId: entryId, from: items)
    let source = resolveInput(sources, isLabelPhoto: isLabelPhoto)
    let confidences = rows.compactMap(\.aiConfidence)
    let confidence =
      confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
    let entry = FoodEntry(
      id: entryId,
      date: date,
      inputType: source.inputType,
      inputText: inputTextOverride ?? inputText(rows),
      imagePath: imagePath,
      macros: rows.reduce(.zero) { $0 + $1.macros },
      aiConfidence: confidence,
      aiSource: source.aiSource,
      aiNotes: notes,
      createdAt: createdAt
    )
    var used: [UUID] = []
    for id in items.filter({ $0.origin == .libraryFood }).compactMap(\.linkedFoodId)
      + extraUsedFoodIds where !used.contains(id)
    {
      used.append(id)
    }
    return LogPayload(
      entry: entry, items: rows, usedFoodIds: used, timeSlot: TimeSlot(date: createdAt))
  }
}

/// Analyze gating (5.6).
public enum AnalyzeGate {
  public struct Fingerprint: Codable, Sendable, Hashable {
    public var text: String
    public var photoId: String?
    public var isLabel: Bool

    public init(text: String, photoId: String?, isLabel: Bool) {
      self.text = text.trimmed
      self.photoId = photoId
      self.isLabel = isLabel
    }

    public var hasInput: Bool { !text.isEmpty || photoId != nil }
  }

  public enum PrimaryAction: Equatable, Sendable {
    case estimate
    case log
  }

  public static let staleMessage =
    "Your photo or description changed. Update the estimate before logging."
  public static let missingNutritionMessage =
    "Remove items with missing nutrition before logging."
  public static let noItemsMessage = "Add at least one item with grams before logging."

  /// Estimate when there is text or a photo that was not analyzed yet. Otherwise log.
  public static func primaryAction(current: Fingerprint, lastAnalyzed: Fingerprint?)
    -> PrimaryAction
  {
    current.hasInput && current != lastAnalyzed ? .estimate : .log
  }

  /// True when an estimate exists but the input changed after it.
  public static func isStale(current: Fingerprint, lastAnalyzed: Fingerprint?) -> Bool {
    guard let lastAnalyzed else { return false }
    return current.hasInput && current != lastAnalyzed
  }

  /// The reason logging is blocked, or nil.
  public static func logBlockReason(_ items: [LogItem]) -> String? {
    if items.contains(where: {
      $0.isNutritionMissing && (LogItemMath.validGrams($0.gramsText) ?? 0) > 0
    }) {
      return missingNutritionMessage
    }
    let valid = items.contains {
      !$0.isNutritionMissing && !$0.name.trimmed.isEmpty
        && LogItemMath.validGrams($0.gramsText) != nil
    }
    return valid ? nil : noItemsMessage
  }
}
