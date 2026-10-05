import Testing

@testable import EZHAKit

struct NumberInputTests {
  @Test func parsesCommaDecimalsSpacesAndRejectsGarbage() {
    #expect(parseNumberInput("12,5") == 12.5)
    #expect(parseNumberInput(" 1 200 ") == 1200)
    #expect(parseNumberInput("1,000.5") == nil)
    #expect(parseNumberInput("3.25") == 3.25)
    #expect(parseNumberInput("") == nil)
    #expect(parseNumberInput("   ") == nil)
    #expect(parseNumberInput("abc") == nil)
    #expect(parseNumberInput("inf") == nil)
  }
}
