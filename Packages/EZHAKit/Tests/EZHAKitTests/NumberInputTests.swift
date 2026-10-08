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

struct NumericInputTests {
  @Test func rejectsInvalidPortionsWithoutClamping() {
    for text in ["", " ", "abc", "NaN", "inf", "-1", "0", "5000.1", "99999"] {
      #expect(NumericInput.portionError(text) != nil)
    }
    for text in ["0.1", "150,5", "5000"] {
      #expect(NumericInput.portionError(text) == nil)
    }
  }

  @Test func nutritionAllowsZeroAndDecimalCommaButRejectsInvalidEdits() {
    for text in ["0", "31,5", "100000"] {
      #expect(NumericInput.nutritionError(text) == nil)
    }
    for text in ["", "abc", "NaN", "-1", "100001", "1e309"] {
      #expect(NumericInput.nutritionError(text) != nil)
    }
  }
}
