import Foundation

/// Port of `src/lib/number.ts`. Trim, remove spaces, accept a comma as the
/// decimal separator when there is no dot. Empty or non-finite input is nil.
public func parseNumberInput(_ text: String) -> Double? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  var normalized = trimmed.replacingOccurrences(of: " ", with: "")
    .replacingOccurrences(of: "\u{00A0}", with: "")
  if normalized.contains(","), !normalized.contains(".") {
    normalized = normalized.replacingOccurrences(of: ",", with: ".")
  }
  guard let value = Double(normalized), value.isFinite else { return nil }
  return value
}
