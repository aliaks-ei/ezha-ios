import Foundation

/// Four macro values. Used for goals, totals, remaining, and item macros.
public struct MacroTotals: Codable, Sendable, Hashable {
  public var calories: Double
  public var protein: Double
  public var carbs: Double
  public var fat: Double

  public init(calories: Double, protein: Double, carbs: Double, fat: Double) {
    self.calories = calories
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
  }

  public static let zero = MacroTotals(calories: 0, protein: 0, carbs: 0, fat: 0)
  /// Goals used when a user has no target (PWA `EXAMPLE_TARGETS`).
  public static let example = MacroTotals(calories: 2100, protein: 140, carbs: 220, fat: 70)

  public static func + (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
    MacroTotals(
      calories: lhs.calories + rhs.calories,
      protein: lhs.protein + rhs.protein,
      carbs: lhs.carbs + rhs.carbs,
      fat: lhs.fat + rhs.fat
    )
  }

  public func scaled(by factor: Double) -> MacroTotals {
    MacroTotals(
      calories: calories * factor,
      protein: protein * factor,
      carbs: carbs * factor,
      fat: fat * factor
    )
  }

  public var rounded: MacroTotals {
    MacroTotals(
      calories: calories.rounded(),
      protein: protein.rounded(),
      carbs: carbs.rounded(),
      fat: fat.rounded()
    )
  }

  public var isAllZero: Bool { calories == 0 && protein == 0 && carbs == 0 && fat == 0 }
}

public struct DailyTarget: Codable, Sendable, Hashable, Identifiable {
  public var id: UUID
  public var userId: UUID?
  public var name: String
  public var caloriesTarget: Double
  public var proteinTarget: Double
  public var carbsTarget: Double
  public var fatTarget: Double
  public var createdAt: Date?

  public init(
    id: UUID, userId: UUID? = nil, name: String, caloriesTarget: Double, proteinTarget: Double,
    carbsTarget: Double, fatTarget: Double, createdAt: Date? = nil
  ) {
    self.id = id
    self.userId = userId
    self.name = name
    self.caloriesTarget = caloriesTarget
    self.proteinTarget = proteinTarget
    self.carbsTarget = carbsTarget
    self.fatTarget = fatTarget
    self.createdAt = createdAt
  }

  public var macros: MacroTotals {
    MacroTotals(
      calories: caloriesTarget, protein: proteinTarget, carbs: carbsTarget, fat: fatTarget)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case name
    case caloriesTarget = "calories_target"
    case proteinTarget = "protein_target"
    case carbsTarget = "carbs_target"
    case fatTarget = "fat_target"
    case createdAt = "created_at"
  }
}

public enum InputType: String, Codable, Sendable {
  case photo
  case text
  case photoText = "photo+text"
}

public enum AISource: String, Codable, Sendable {
  case foodPhoto = "food_photo"
  case labelPhoto = "label_photo"
  case text
  case unknown
  case library
}

public struct FoodEntry: Codable, Sendable, Hashable, Identifiable {
  public var id: UUID
  public var userId: UUID?
  public var date: DateKey
  public var inputType: InputType
  public var inputText: String?
  public var imagePath: String?
  public var calories: Double
  public var protein: Double
  public var carbs: Double
  public var fat: Double
  public var aiConfidence: Double?
  public var aiSource: AISource
  public var aiNotes: String
  public var createdAt: Date?

  public init(
    id: UUID, userId: UUID? = nil, date: DateKey, inputType: InputType, inputText: String?,
    imagePath: String?, macros: MacroTotals, aiConfidence: Double?, aiSource: AISource,
    aiNotes: String, createdAt: Date?
  ) {
    self.id = id
    self.userId = userId
    self.date = date
    self.inputType = inputType
    self.inputText = inputText
    self.imagePath = imagePath
    self.calories = macros.calories
    self.protein = macros.protein
    self.carbs = macros.carbs
    self.fat = macros.fat
    self.aiConfidence = aiConfidence
    self.aiSource = aiSource
    self.aiNotes = aiNotes
    self.createdAt = createdAt
  }

  public var macros: MacroTotals {
    MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case date
    case inputType = "input_type"
    case inputText = "input_text"
    case imagePath = "image_path"
    case calories, protein, carbs, fat
    case aiConfidence = "ai_confidence"
    case aiSource = "ai_source"
    case aiNotes = "ai_notes"
    case createdAt = "created_at"
  }
}

public struct FoodEntryItem: Codable, Sendable, Hashable, Identifiable {
  public var id: UUID
  public var entryId: UUID
  public var userId: UUID?
  public var name: String
  public var grams: Double
  public var calories: Double
  public var protein: Double
  public var carbs: Double
  public var fat: Double
  public var aiConfidence: Double?
  public var aiNotes: String
  public var createdAt: Date?

  public init(
    id: UUID, entryId: UUID, userId: UUID? = nil, name: String, grams: Double, macros: MacroTotals,
    aiConfidence: Double?, aiNotes: String, createdAt: Date? = nil
  ) {
    self.id = id
    self.entryId = entryId
    self.userId = userId
    self.name = name
    self.grams = grams
    self.calories = macros.calories
    self.protein = macros.protein
    self.carbs = macros.carbs
    self.fat = macros.fat
    self.aiConfidence = aiConfidence
    self.aiNotes = aiNotes
    self.createdAt = createdAt
  }

  public var macros: MacroTotals {
    MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case entryId = "entry_id"
    case userId = "user_id"
    case name, grams, calories, protein, carbs, fat
    case aiConfidence = "ai_confidence"
    case aiNotes = "ai_notes"
    case createdAt = "created_at"
  }
}

/// A `food_entries` row with its items, as `get_day` returns it.
public struct DayEntry: Codable, Sendable, Hashable, Identifiable {
  public var entry: FoodEntry
  public var items: [FoodEntryItem]
  /// True while the entry waits in the outbox. Never sent to the server.
  public var isPending: Bool

  public var id: UUID { entry.id }

  public init(entry: FoodEntry, items: [FoodEntryItem], isPending: Bool = false) {
    self.entry = entry
    self.items = items
    self.isPending = isPending
  }

  enum ExtraKeys: String, CodingKey {
    case items
    case isPending = "is_pending"
  }

  public init(from decoder: any Decoder) throws {
    entry = try FoodEntry(from: decoder)
    let container = try decoder.container(keyedBy: ExtraKeys.self)
    items = try container.decodeIfPresent([FoodEntryItem].self, forKey: .items) ?? []
    isPending = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? false
  }

  public func encode(to encoder: any Encoder) throws {
    try entry.encode(to: encoder)
    var container = encoder.container(keyedBy: ExtraKeys.self)
    try container.encode(items, forKey: .items)
    try container.encode(isPending, forKey: .isPending)
  }
}

/// Everything the day screen needs, from the `get_day` RPC.
public struct DayBundle: Codable, Sendable, Hashable {
  public var date: DateKey
  public var target: DailyTarget?
  public var goals: MacroTotals
  public var totals: MacroTotals
  public var targets: [DailyTarget]
  public var entries: [DayEntry]

  public init(
    date: DateKey, target: DailyTarget?, goals: MacroTotals, totals: MacroTotals,
    targets: [DailyTarget], entries: [DayEntry]
  ) {
    self.date = date
    self.target = target
    self.goals = goals
    self.totals = totals
    self.targets = targets
    self.entries = entries
  }
}

public enum FoodUnitType: String, Codable, Sendable {
  case per100g = "per_100g"
  case perServing = "per_serving"
}

public struct SavedFood: Codable, Sendable, Hashable, Identifiable {
  public var id: UUID
  public var userId: UUID?
  public var name: String
  public var unitType: FoodUnitType
  public var servingSize: Double?
  public var servingUnit: String?
  public var caloriesPer100g: Double
  public var proteinPer100g: Double
  public var carbsPer100g: Double
  public var fatPer100g: Double
  public var caloriesPerServing: Double
  public var proteinPerServing: Double
  public var carbsPerServing: Double
  public var fatPerServing: Double
  public var isMeal: Bool
  public var isFavorite: Bool
  public var lastUsedAt: Date?
  public var createdAt: Date?
  public var updatedAt: Date?

  public init(
    id: UUID, userId: UUID? = nil, name: String, unitType: FoodUnitType = .per100g,
    servingSize: Double? = nil, servingUnit: String? = nil, per100g: MacroTotals = .zero,
    perServing: MacroTotals = .zero, isMeal: Bool = false, isFavorite: Bool = false,
    lastUsedAt: Date? = nil, createdAt: Date? = nil, updatedAt: Date? = nil
  ) {
    self.id = id
    self.userId = userId
    self.name = name
    self.unitType = unitType
    self.servingSize = servingSize
    self.servingUnit = servingUnit
    self.caloriesPer100g = per100g.calories
    self.proteinPer100g = per100g.protein
    self.carbsPer100g = per100g.carbs
    self.fatPer100g = per100g.fat
    self.caloriesPerServing = perServing.calories
    self.proteinPerServing = perServing.protein
    self.carbsPerServing = perServing.carbs
    self.fatPerServing = perServing.fat
    self.isMeal = isMeal
    self.isFavorite = isFavorite
    self.lastUsedAt = lastUsedAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var per100g: MacroTotals {
    MacroTotals(
      calories: caloriesPer100g, protein: proteinPer100g, carbs: carbsPer100g, fat: fatPer100g)
  }

  public var perServing: MacroTotals {
    MacroTotals(
      calories: caloriesPerServing, protein: proteinPerServing, carbs: carbsPerServing,
      fat: fatPerServing)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case name
    case unitType = "unit_type"
    case servingSize = "serving_size"
    case servingUnit = "serving_unit"
    case caloriesPer100g = "calories_per_100g"
    case proteinPer100g = "protein_per_100g"
    case carbsPer100g = "carbs_per_100g"
    case fatPer100g = "fat_per_100g"
    case caloriesPerServing = "calories_per_serving"
    case proteinPerServing = "protein_per_serving"
    case carbsPerServing = "carbs_per_serving"
    case fatPerServing = "fat_per_serving"
    case isMeal = "is_meal"
    case isFavorite = "is_favorite"
    case lastUsedAt = "last_used_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    userId = try c.decodeIfPresent(UUID.self, forKey: .userId)
    name = try c.decode(String.self, forKey: .name)
    unitType = try c.decodeIfPresent(FoodUnitType.self, forKey: .unitType) ?? .per100g
    servingSize = try c.decodeIfPresent(Double.self, forKey: .servingSize)
    servingUnit = try c.decodeIfPresent(String.self, forKey: .servingUnit)
    caloriesPer100g = try c.decodeIfPresent(Double.self, forKey: .caloriesPer100g) ?? 0
    proteinPer100g = try c.decodeIfPresent(Double.self, forKey: .proteinPer100g) ?? 0
    carbsPer100g = try c.decodeIfPresent(Double.self, forKey: .carbsPer100g) ?? 0
    fatPer100g = try c.decodeIfPresent(Double.self, forKey: .fatPer100g) ?? 0
    caloriesPerServing = try c.decodeIfPresent(Double.self, forKey: .caloriesPerServing) ?? 0
    proteinPerServing = try c.decodeIfPresent(Double.self, forKey: .proteinPerServing) ?? 0
    carbsPerServing = try c.decodeIfPresent(Double.self, forKey: .carbsPerServing) ?? 0
    fatPerServing = try c.decodeIfPresent(Double.self, forKey: .fatPerServing) ?? 0
    isMeal = try c.decodeIfPresent(Bool.self, forKey: .isMeal) ?? false
    isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
  }
}

public struct SavedMealIngredient: Codable, Sendable, Hashable, Identifiable {
  public var id: UUID
  public var mealId: UUID?
  public var userId: UUID?
  public var name: String
  public var grams: Double
  public var calories: Double
  public var protein: Double
  public var carbs: Double
  public var fat: Double
  public var linkedFoodId: UUID?
  public var createdAt: Date?

  public init(
    id: UUID = UUID(), mealId: UUID? = nil, userId: UUID? = nil, name: String, grams: Double,
    macros: MacroTotals, linkedFoodId: UUID? = nil, createdAt: Date? = nil
  ) {
    self.id = id
    self.mealId = mealId
    self.userId = userId
    self.name = name
    self.grams = grams
    self.calories = macros.calories
    self.protein = macros.protein
    self.carbs = macros.carbs
    self.fat = macros.fat
    self.linkedFoodId = linkedFoodId
    self.createdAt = createdAt
  }

  public var macros: MacroTotals {
    MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case mealId = "meal_id"
    case userId = "user_id"
    case name, grams, calories, protein, carbs, fat
    case linkedFoodId = "linked_food_id"
    case createdAt = "created_at"
  }
}

/// Shared JSON coding for server rows and the file cache. Postgres sends
/// timestamps like `2026-10-05T15:33:40.723895+00:00`.
extension JSONDecoder {
  public static var ezha: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)
      if let date = ISO8601Timestamp.parse(string) { return date }
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid date: \(string)")
    }
    return decoder
  }
}

extension JSONEncoder {
  public static var ezha: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(ISO8601Timestamp.format(date))
    }
    return encoder
  }
}

enum ISO8601Timestamp {
  static func parse(_ string: String) -> Date? {
    // Postgres sends up to 6 fraction digits. ISO8601FormatStyle wants exactly 3.
    var normalized = string.replacingOccurrences(of: " ", with: "T")
    if let dot = normalized.firstIndex(of: ".") {
      let fractionEnd =
        normalized[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
        ?? normalized.endIndex
      let digits = String(normalized[normalized.index(after: dot)..<fractionEnd].prefix(3))
      let padded = digits.padding(toLength: 3, withPad: "0", startingAt: 0)
      normalized.replaceSubrange(dot..<fractionEnd, with: "." + padded)
    }
    for format in [Date.ISO8601FormatStyle(includingFractionalSeconds: true), .iso8601] {
      if let date = try? format.parse(normalized) { return date }
    }
    return nil
  }

  static func format(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
  }
}
