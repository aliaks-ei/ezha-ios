import Foundation

/// Insert or update body for `saved_foods`. Port of `SavedFoodDraft`.
public struct SavedFoodDraft: Codable, Sendable, Hashable {
  public var name: String
  public var unitType: FoodUnitType
  public var servingSize: Double?
  public var servingUnit: String?
  public var per100g: MacroTotals
  public var perServing: MacroTotals

  public init(
    name: String, unitType: FoodUnitType, servingSize: Double?, servingUnit: String?,
    per100g: MacroTotals, perServing: MacroTotals
  ) {
    self.name = name
    self.unitType = unitType
    self.servingSize = servingSize
    self.servingUnit = servingUnit
    self.per100g = per100g
    self.perServing = perServing
  }

  enum CodingKeys: String, CodingKey {
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
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    unitType = try c.decode(FoodUnitType.self, forKey: .unitType)
    servingSize = try c.decodeIfPresent(Double.self, forKey: .servingSize)
    servingUnit = try c.decodeIfPresent(String.self, forKey: .servingUnit)
    per100g = MacroTotals(
      calories: try c.decode(Double.self, forKey: .caloriesPer100g),
      protein: try c.decode(Double.self, forKey: .proteinPer100g),
      carbs: try c.decode(Double.self, forKey: .carbsPer100g),
      fat: try c.decode(Double.self, forKey: .fatPer100g))
    perServing = MacroTotals(
      calories: try c.decode(Double.self, forKey: .caloriesPerServing),
      protein: try c.decode(Double.self, forKey: .proteinPerServing),
      carbs: try c.decode(Double.self, forKey: .carbsPerServing),
      fat: try c.decode(Double.self, forKey: .fatPerServing))
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(name, forKey: .name)
    try c.encode(unitType, forKey: .unitType)
    try c.encode(servingSize, forKey: .servingSize)
    try c.encode(servingUnit, forKey: .servingUnit)
    try c.encode(per100g.calories, forKey: .caloriesPer100g)
    try c.encode(per100g.protein, forKey: .proteinPer100g)
    try c.encode(per100g.carbs, forKey: .carbsPer100g)
    try c.encode(per100g.fat, forKey: .fatPer100g)
    try c.encode(perServing.calories, forKey: .caloriesPerServing)
    try c.encode(perServing.protein, forKey: .proteinPerServing)
    try c.encode(perServing.carbs, forKey: .carbsPerServing)
    try c.encode(perServing.fat, forKey: .fatPerServing)
  }
}

public struct LibraryDraftError: Error, Equatable, Sendable, LocalizedError {
  public let message: String
  public var errorDescription: String? { message }

  public static let missingName = LibraryDraftError(message: "Please enter a food name.")
  public static let missingPhotoName = LibraryDraftError(
    message: "Please enter a food name to save to Library.")
  public static let invalidMacros = LibraryDraftError(message: "Please enter valid macro values.")
  public static let missingServing = LibraryDraftError(message: "Please enter grams per serving.")
}

/// Port of `src/features/add-log/library-save-service.ts`.
public enum LibraryDrafts {
  public static let defaultServingUnit = "serving"

  public struct ManualInput: Sendable {
    public var name: String
    public var unitType: FoodUnitType
    public var servingGrams: Double?
    public var servingUnit: String
    /// Calories, protein, carbs, fat per 100 g. Nil when a field is not a number.
    public var per100g: [Double?]

    public init(
      name: String, unitType: FoodUnitType, servingGrams: Double?, servingUnit: String,
      per100g: [Double?]
    ) {
      self.name = name
      self.unitType = unitType
      self.servingGrams = servingGrams
      self.servingUnit = servingUnit
      self.per100g = per100g
    }
  }

  /// Name required. Macros per 100 g. Per serving needs serving grams > 0.
  public static func manualDraft(_ input: ManualInput) -> Result<SavedFoodDraft, LibraryDraftError>
  {
    let name = input.name.trimmed
    guard !name.isEmpty else { return .failure(.missingName) }
    guard let per100 = macros(from: input.per100g) else { return .failure(.invalidMacros) }
    var servingSize: Double?
    var servingUnit: String?
    var perServing = MacroTotals.zero
    if input.unitType == .perServing {
      guard let grams = input.servingGrams, grams > 0 else { return .failure(.missingServing) }
      servingSize = grams
      servingUnit = input.servingUnit.trimmed.nonEmpty ?? defaultServingUnit
      perServing = per100.scaled(by: grams / 100)
    }
    return .success(
      SavedFoodDraft(
        name: name, unitType: input.unitType, servingSize: servingSize, servingUnit: servingUnit,
        per100g: per100, perServing: perServing))
  }

  /// Photo food: display macros. A label with grams eaten converts back to per 100 g.
  public static func photoDraft(
    name: String, display: [Double?], isLabelPhoto: Bool, labelGrams: Double?
  ) -> Result<SavedFoodDraft, LibraryDraftError> {
    let name = name.trimmed
    guard !name.isEmpty else { return .failure(.missingPhotoName) }
    guard let values = macros(from: display) else { return .failure(.invalidMacros) }
    let per100 =
      isLabelPhoto ? LogItemMath.per100gFromDisplay(values, grams: labelGrams) : values
    return .success(
      SavedFoodDraft(
        name: name, unitType: .per100g, servingSize: nil, servingUnit: nil, per100g: per100,
        perServing: .zero))
  }

  /// Exact case-insensitive name match among non-meal foods.
  public static func duplicate(of name: String, in foods: [SavedFood]) -> SavedFood? {
    let target = name.trimmed.lowercased()
    guard !target.isEmpty else { return nil }
    return foods.first { !$0.isMeal && $0.name.trimmed.lowercased() == target }
  }

  /// First non-empty of: selected library food name, item names joined with " + ",
  /// description text, AI food name.
  public static func suggestedName(
    selectedLibraryFoodName: String?, itemNames: [String], descriptionText: String,
    aiFoodName: String?
  ) -> String? {
    if let selected = selectedLibraryFoodName?.trimmed.nonEmpty { return selected }
    let names = itemNames.map(\.trimmed).filter { !$0.isEmpty }
    if !names.isEmpty { return names.joined(separator: " + ") }
    if let text = descriptionText.trimmed.nonEmpty { return text }
    return aiFoodName?.trimmed.nonEmpty
  }

  private static func macros(from values: [Double?]) -> MacroTotals? {
    let finite = values.compactMap { $0 }.filter(\.isFinite)
    guard values.count == 4, finite.count == 4 else { return nil }
    return MacroTotals(calories: finite[0], protein: finite[1], carbs: finite[2], fat: finite[3])
  }
}
