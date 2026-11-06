import Foundation

/// "Log again" (PET-107): copy a logged entry to a chosen day with edited amounts.
public enum LogAgain {
  /// One editable item per logged item. Macros scale by `newGrams / oldGrams`.
  /// Items logged at 0 g (or a non-finite amount) cannot scale and are left out.
  public static func items(from entry: DayEntry) -> [LogItem] {
    entry.items.compactMap { item in
      guard item.grams.isFinite, item.grams > 0 else { return nil }
      return LogItem(
        name: item.name,
        gramsText: Macros.format(item.grams, maxFractionDigits: 1),
        unit: item.unit,
        macroBasis: .perOriginal,
        baseGrams: item.grams,
        base: item.macros,
        origin: .ai,
        aiConfidence: item.aiConfidence,
        aiNotes: item.aiNotes)
    }
  }

  /// True when there is at least one item and every item is in (0, 5000].
  public static func isValid(_ items: [LogItem]) -> Bool {
    LogItemMath.isQuickLogValid(items: items, quantity: 1)
  }

  /// A new entry on `date` with new ids. The original entry does not change.
  public static func payload(
    from entry: DayEntry, items: [LogItem], date: DateKey, createdAt: Date = .now
  ) -> LogPayload {
    let newId = UUID()
    let rows = EntryPayload.entryItems(entryId: newId, from: items)
    let totals = rows.reduce(MacroTotals.zero) { $0 + $1.macros }
    var copy = entry.entry
    copy.id = newId
    copy.date = date
    copy.createdAt = createdAt
    copy.calories = totals.calories
    copy.protein = totals.protein
    copy.carbs = totals.carbs
    copy.fat = totals.fat
    return LogPayload(entry: copy, items: rows, usedFoodIds: [])
  }
}
