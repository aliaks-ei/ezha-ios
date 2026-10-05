import Foundation

/// A day as `yyyy-MM-dd` in the device's calendar and time zone. Never UTC.
/// Port of `src/lib/date.ts` and `src/lib/day-navigation.ts`.
public struct DateKey: Codable, Sendable, Hashable, Comparable, Identifiable,
  CustomStringConvertible
{
  public let rawValue: String

  /// Returns nil when the string is not a real `yyyy-MM-dd` date.
  public init?(_ string: String, calendar: Calendar = .current) {
    let parts = string.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
      let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
    else { return nil }
    let check = calendar.dateComponents([.year, .month, .day], from: date)
    guard check.year == year, check.month == month, check.day == day else { return nil }
    rawValue = string
  }

  public init(_ date: Date, calendar: Calendar = .current) {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    rawValue = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  public static func today(calendar: Calendar = .current, now: Date = .now) -> DateKey {
    DateKey(now, calendar: calendar)
  }

  /// Start of the day in `calendar`.
  public func date(calendar: Calendar = .current) -> Date {
    let parts = rawValue.split(separator: "-").compactMap { Int($0) }
    let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
    return calendar.date(from: components) ?? .now
  }

  public func adding(days: Int, calendar: Calendar = .current) -> DateKey {
    let next = calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) ?? .now
    return DateKey(next, calendar: calendar)
  }

  /// An invalid or future date becomes today.
  public static func clamp(_ string: String, today: DateKey, calendar: Calendar = .current)
    -> DateKey
  {
    guard let key = DateKey(string, calendar: calendar), key <= today else { return today }
    return key
  }

  public func previous(calendar: Calendar = .current) -> DateKey {
    adding(days: -1, calendar: calendar)
  }

  /// +1 day, clamped to today.
  public func next(today: DateKey, calendar: Calendar = .current) -> DateKey {
    min(adding(days: 1, calendar: calendar), today)
  }

  /// "Today", or a short date like "Oct 4".
  public func label(today: DateKey, locale: Locale = .current, calendar: Calendar = .current)
    -> String
  {
    if self == today { return String(localized: "Today", bundle: .module) }
    return date(calendar: calendar).formatted(
      Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        .month(.abbreviated).day())
  }

  /// "Today", or a date with the weekday like "Sat, Oct 4". Used as the Today title.
  public func titleLabel(
    today: DateKey, locale: Locale = .current, calendar: Calendar = .current
  ) -> String {
    if self == today { return String(localized: "Today", bundle: .module) }
    return date(calendar: calendar).formatted(
      Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        .weekday(.abbreviated).month(.abbreviated).day())
  }

  public var description: String { rawValue }

  public var id: String { rawValue }

  public static func < (lhs: DateKey, rhs: DateKey) -> Bool { lhs.rawValue < rhs.rawValue }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    // Date keys are never interpreted in another time zone, so only the format is checked.
    guard let key = DateKey(string, calendar: Calendar(identifier: .gregorian)) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid date key: \(string)")
    }
    self = key
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
