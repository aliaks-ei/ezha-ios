import Foundation
import Testing

@testable import EZHAKit

struct WaterTests {
  let us = Locale(identifier: "en_US")

  @Test func unitsConvertToWholeMillilitres() {
    #expect(WaterUnit.ml.toMillilitres(330) == 330)
    #expect(WaterUnit.l.toMillilitres(1.5) == 1500)
    #expect(WaterUnit.cup.toMillilitres(2) == 480)
    #expect(WaterUnit.glass.toMillilitres(1) == 250)
    #expect(WaterUnit.bottle.toMillilitres(0.5) == 250)
    #expect(WaterUnit.flOz.toMillilitres(8) == 237)
    #expect(WaterUnit.flOz.toMillilitres(1) == 30)
  }

  @Test func unitNamesUseSingularForOne() {
    #expect(WaterUnit.cup.name(for: 1) == "cup")
    #expect(WaterUnit.cup.name(for: 2) == "cups")
    #expect(WaterUnit.glass.name(for: 0.5) == "glasses")
    #expect(WaterUnit.ml.name(for: 1) == "ml")
    #expect(WaterUnit.ml.definition == nil)
    #expect(WaterUnit.cup.definition == "1 cup = 240 ml")
  }

  @Test func amountInputAcceptsCommaAndRejectsZeroAndTooMuch() {
    #expect(Water.millilitres("330", unit: .ml) == 330)
    #expect(Water.millilitres("1,5", unit: .l) == 1500)
    #expect(Water.millilitres(" 2 ", unit: .glass) == 500)
    #expect(Water.millilitres("0", unit: .ml) == nil)
    #expect(Water.millilitres("-1", unit: .ml) == nil)
    #expect(Water.millilitres("abc", unit: .ml) == nil)
    #expect(Water.millilitres("", unit: .ml) == nil)
    #expect(Water.millilitres("0.2", unit: .ml) == nil)
    #expect(Water.millilitres("10", unit: .l) == 10_000)
    #expect(Water.millilitres("10.1", unit: .l) == nil)
    #expect(Water.amountError("0", unit: .ml) != nil)
    #expect(Water.amountError("250", unit: .ml) == nil)
  }

  @Test func targetInputAllowsUpTo20Litres() {
    #expect(Water.targetMillilitres("2", unit: .l) == 2000)
    #expect(Water.targetMillilitres("2500", unit: .ml) == 2500)
    #expect(Water.targetMillilitres("20", unit: .l) == 20_000)
    #expect(Water.targetMillilitres("21", unit: .l) == nil)
    #expect(Water.targetMillilitres("0", unit: .ml) == nil)
    #expect(Water.targetError("", unit: .ml) != nil)
  }

  @Test func statusIsLeftReachedOverOrNoTarget() {
    #expect(Water.status(drunk: 1250, target: 2000) == .left(750))
    #expect(Water.status(drunk: 2000, target: 2000) == .reached)
    #expect(Water.status(drunk: 2400, target: 2000) == .over(400))
    #expect(Water.status(drunk: 1250, target: nil) == .noTarget)
    #expect(Water.status(drunk: 1250, target: 0) == .noTarget)
    #expect(Water.status(drunk: 0, target: 2000) == .left(2000))
  }

  @Test func progressIsCappedAndZeroWithoutTarget() {
    #expect(Water.progress(drunk: 500, target: 2000) == 0.25)
    #expect(Water.progress(drunk: 3000, target: 2000) == 1)
    #expect(Water.progress(drunk: 500, target: nil) == 0)
  }

  @Test func totalSumsEntries() {
    let date = key("2026-10-07")
    let entries = [250, 500, 177.44].map { WaterEntry(date: date, amountMl: $0) }
    #expect(Water.total(entries) == 927)
    #expect(Water.total([]) == 0)
  }

  @Test func formatsMillilitresAndTargets() {
    #expect(Water.format(1250, locale: us) == "1,250 ml")
    #expect(Water.format(249.6, locale: us) == "250 ml")
    #expect(Water.number(2000, locale: us) == "2,000")
    #expect(Water.formatTarget(2000, locale: us) == "2 l")
    #expect(Water.formatTarget(2500, locale: us) == "2.5 l")
    #expect(Water.formatTarget(1750, locale: us) == "1,750 ml")
    #expect(Water.formatTarget(800, locale: us) == "800 ml")
  }

  @Test func dayBundleDecodesWaterAndOlderPayloadsWithout() throws {
    let older = """
      {"date": "2026-10-07", "target": null, "goals": {"calories": 2100, "protein": 140, "carbs": 220, "fat": 70},
       "totals": {"calories": 0, "protein": 0, "carbs": 0, "fat": 0}, "targets": [], "entries": []}
      """
    let old = try JSONDecoder.ezha.decode(DayBundle.self, from: Data(older.utf8))
    #expect(old.water.isEmpty)
    #expect(old.waterTargetMl == nil)

    let current = """
      {"date": "2026-10-07", "target": {"id": "11111111-1111-1111-1111-111111111111", "name": "Basic",
         "calories_target": 2100, "protein_target": 140, "carbs_target": 220, "fat_target": 70,
         "water_target_ml": 2000},
       "goals": {"calories": 2100, "protein": 140, "carbs": 220, "fat": 70},
       "water_target_ml": 2000,
       "totals": {"calories": 0, "protein": 0, "carbs": 0, "fat": 0}, "targets": [], "entries": [],
       "water": [{"id": "22222222-2222-2222-2222-222222222222", "user_id": "33333333-3333-3333-3333-333333333333",
         "date": "2026-10-07", "amount_ml": 330, "created_at": "2026-10-07T10:00:00+00:00"}]}
      """
    let bundle = try JSONDecoder.ezha.decode(DayBundle.self, from: Data(current.utf8))
    #expect(bundle.waterTargetMl == 2000)
    #expect(bundle.target?.waterTargetMl == 2000)
    #expect(bundle.water.count == 1)
    #expect(bundle.water[0].amountMl == 330)
    #expect(bundle.water[0].isPending == false)
    #expect(bundle.waterTotal == 330)

    // The cache round trip keeps water.
    let again = try JSONDecoder.ezha.decode(
      DayBundle.self, from: JSONEncoder.ezha.encode(bundle))
    #expect(again == bundle)
  }

  @Test func defaultPresetsStartWithGlassAndBottle() {
    #expect(WaterPreset.defaults.prefix(Water.quickAddCount).map(\.amountMl) == [250, 500])
  }
}
