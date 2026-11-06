import Foundation

/// One drink of water, from `water_entries`. Amounts are millilitres.
/// Water never changes calories or macros.
public struct WaterEntry: Codable, Sendable, Hashable, Identifiable {
  public var id: UUID
  public var userId: UUID?
  public var date: DateKey
  public var amountMl: Double
  public var createdAt: Date?
  /// True while the entry waits in the outbox. Never sent to the server.
  public var isPending: Bool

  public init(
    id: UUID = UUID(), userId: UUID? = nil, date: DateKey, amountMl: Double,
    createdAt: Date? = .now, isPending: Bool = false
  ) {
    self.id = id
    self.userId = userId
    self.date = date
    self.amountMl = amountMl
    self.createdAt = createdAt
    self.isPending = isPending
  }

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case date
    case amountMl = "amount_ml"
    case createdAt = "created_at"
    case isPending = "is_pending"
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    userId = try c.decodeIfPresent(UUID.self, forKey: .userId)
    date = try c.decode(DateKey.self, forKey: .date)
    amountMl = try c.decode(Double.self, forKey: .amountMl)
    createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    isPending = try c.decodeIfPresent(Bool.self, forKey: .isPending) ?? false
  }
}

/// A unit for entering water. Every amount is saved in millilitres.
public enum WaterUnit: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
  case ml
  case l
  case flOz = "fl_oz"
  case cup
  case glass
  case bottle

  public var id: String { rawValue }

  /// Millilitres in one unit. A cup is 240 ml (US legal cup), a US fluid ounce 29.5735 ml.
  public var millilitres: Double {
    switch self {
    case .ml: 1
    case .l: 1000
    case .flOz: 29.5735
    case .cup: 240
    case .glass: 250
    case .bottle: 500
    }
  }

  /// The amount in whole millilitres.
  public func toMillilitres(_ amount: Double) -> Double {
    (amount * millilitres).rounded()
  }

  /// Picker title: "ml", "l", "fl oz", "Cup", "Glass", "Bottle".
  public var title: String {
    switch self {
    case .ml: String(localized: "ml")
    case .l: String(localized: "l")
    case .flOz: String(localized: "fl oz")
    case .cup: String(localized: "Cup")
    case .glass: String(localized: "Glass")
    case .bottle: String(localized: "Bottle")
    }
  }

  /// The unit after a number: "ml", "l", "fl oz", "cup" or "cups".
  public func name(for amount: Double) -> String {
    let one = amount == 1
    switch self {
    case .ml: return String(localized: "ml")
    case .l: return String(localized: "l")
    case .flOz: return String(localized: "fl oz")
    case .cup: return one ? String(localized: "cup") : String(localized: "cups")
    case .glass: return one ? String(localized: "glass") : String(localized: "glasses")
    case .bottle: return one ? String(localized: "bottle") : String(localized: "bottles")
    }
  }

  /// "1 cup = 240 ml". Nil for ml.
  public var definition: String? {
    switch self {
    case .ml: nil
    case .l: String(localized: "1 l = 1,000 ml")
    case .flOz: String(localized: "1 US fl oz = 29.6 ml")
    case .cup: String(localized: "1 cup = 240 ml")
    case .glass: String(localized: "1 glass = 250 ml")
    case .bottle: String(localized: "1 bottle = 500 ml")
    }
  }
}

/// A named amount for one-tap logging. The first two show on Today.
public struct WaterPreset: Codable, Sendable, Hashable, Identifiable {
  public var id: UUID
  public var name: String
  public var amountMl: Double

  public init(id: UUID = UUID(), name: String, amountMl: Double) {
    self.id = id
    self.name = name
    self.amountMl = amountMl
  }

  public static let defaults = [
    WaterPreset(name: String(localized: "Glass"), amountMl: 250),
    WaterPreset(name: String(localized: "Bottle"), amountMl: 500),
    WaterPreset(name: String(localized: "Mug"), amountMl: 300),
    WaterPreset(name: String(localized: "Large bottle"), amountMl: 1000),
  ]
}

/// Water sums, the target status, input checks, and display.
public enum Water {
  /// The largest single entry, the same as the `water_entries` check.
  public static let maxEntryMl: Double = 10_000
  /// The largest daily target the editor accepts.
  public static let maxTargetMl: Double = 20_000
  /// The target the editor suggests when the water target is turned on.
  public static let defaultTargetMl: Double = 2000
  /// How many presets show as buttons on Today.
  public static let quickAddCount = 2

  /// Total millilitres, rounded.
  public static func total(_ entries: [WaterEntry]) -> Double {
    entries.reduce(0) { $0 + $1.amountMl }.rounded()
  }

  public enum Status: Equatable, Sendable {
    case noTarget
    case left(Double)
    case reached
    case over(Double)
  }

  /// "750 ml left", "Target reached", "400 ml over", or no target (nil or not above 0).
  public static func status(drunk: Double, target: Double?) -> Status {
    guard let target, target > 0 else { return .noTarget }
    let difference = target.rounded() - drunk.rounded()
    if difference > 0 { return .left(difference) }
    if difference == 0 { return .reached }
    return .over(-difference)
  }

  /// Bar progress from 0 to 1. 0 without a target.
  public static func progress(drunk: Double, target: Double?) -> Double {
    guard let target, target > 0 else { return 0 }
    return min(max(drunk / target, 0), 1)
  }

  /// The typed amount in whole millilitres, or nil when it is not a valid entry.
  public static func millilitres(_ text: String, unit: WaterUnit) -> Double? {
    guard let value = parseNumberInput(text), value > 0 else { return nil }
    let ml = unit.toMillilitres(value)
    guard ml >= 1, ml <= maxEntryMl else { return nil }
    return ml
  }

  public static func amountError(_ text: String, unit: WaterUnit) -> String? {
    millilitres(text, unit: unit) == nil
      ? String(localized: "Enter an amount from 1 ml to 10 l.") : nil
  }

  /// The target in whole millilitres from the editor text, or nil when it is not valid.
  public static func targetMillilitres(_ text: String, unit: WaterUnit) -> Double? {
    guard let value = parseNumberInput(text), value > 0 else { return nil }
    let ml = unit.toMillilitres(value)
    guard ml >= 1, ml <= maxTargetMl else { return nil }
    return ml
  }

  public static func targetError(_ text: String, unit: WaterUnit) -> String? {
    targetMillilitres(text, unit: unit) == nil
      ? String(localized: "Enter a target from 1 ml to 20 l.") : nil
  }

  /// "1,250 ml".
  public static func format(_ ml: Double, locale: Locale = .current) -> String {
    let number = ml.rounded().formatted(
      .number.precision(.fractionLength(0)).locale(locale))
    return String(localized: "\(number) ml")
  }

  /// The number only, "1,250", for a large value next to a smaller unit.
  public static func number(_ ml: Double, locale: Locale = .current) -> String {
    ml.rounded().formatted(.number.precision(.fractionLength(0)).locale(locale))
  }

  /// "2 l" or "2.5 l" when the target is whole hundreds of millilitres, else "1,750 ml".
  public static func formatTarget(_ ml: Double, locale: Locale = .current) -> String {
    let rounded = ml.rounded()
    guard rounded >= 1000, rounded.truncatingRemainder(dividingBy: 100) == 0 else {
      return format(rounded, locale: locale)
    }
    let litres = (rounded / 1000).formatted(
      .number.precision(.fractionLength(0...1)).locale(locale))
    return String(localized: "\(litres) l")
  }
}
