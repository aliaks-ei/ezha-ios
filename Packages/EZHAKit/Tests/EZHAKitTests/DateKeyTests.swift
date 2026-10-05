import Foundation
import Testing

@testable import EZHAKit

struct DateKeyTests {
  let today = key("2026-05-09")
  let enUS = Locale(identifier: "en_US")

  @Test func labelsTodayAndFormatsHistoricalDays() {
    #expect(key("2026-05-09").label(today: today, locale: enUS, calendar: pacific) == "Today")
    #expect(key("2026-05-08").label(today: today, locale: enUS, calendar: pacific) == "May 8")
    #expect(key("2026-05-01").label(today: today, locale: enUS, calendar: pacific) == "May 1")
    #expect(
      key("2026-10-04").titleLabel(today: key("2026-10-05"), locale: enUS, calendar: pacific)
        == "Sun, Oct 4")
  }

  @Test func movesBackAndClampsForwardAtToday() {
    #expect(key("2026-05-09").previous(calendar: pacific) == key("2026-05-08"))
    #expect(key("2026-05-08").next(today: today, calendar: pacific) == today)
    #expect(key("2026-05-09").next(today: today, calendar: pacific) == today)
    #expect(key("2026-03-01").previous(calendar: pacific) == key("2026-02-28"))
  }

  @Test func rejectsInvalidAndFutureDates() {
    #expect(DateKey.clamp("not-a-date", today: today, calendar: pacific) == today)
    #expect(DateKey.clamp("2026-05-10", today: today, calendar: pacific) == today)
    #expect(DateKey.clamp("2026-05-08", today: today, calendar: pacific) == key("2026-05-08"))
    #expect(DateKey("2026-02-30", calendar: pacific) == nil)
  }

  @Test func usesTheCalendarTimeZoneNotUTC() {
    // 2026-05-10 05:00 UTC is still May 9 in Los Angeles.
    let instant = Date(timeIntervalSince1970: 1_778_389_200)
    #expect(DateKey.today(calendar: pacific, now: instant) == key("2026-05-09"))
  }
}
