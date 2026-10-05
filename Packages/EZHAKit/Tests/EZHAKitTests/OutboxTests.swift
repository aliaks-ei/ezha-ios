import Foundation
import Testing

@testable import EZHAKit

struct OutboxTests {
  let now = Date(timeIntervalSince1970: 1_000_000)

  func makeOutbox() throws -> OutboxProcessor {
    OutboxProcessor(modelContainer: try LocalStore.makeContainer(inMemory: true))
  }

  func payload() -> LogPayload {
    EntryPayload.build(
      date: key("2026-10-05"), imagePath: nil, items: [LogItemMath.fromSavedFood(sampleFood())],
      sources: UsedSources(usedLibrary: true), isLabelPhoto: false)
  }

  @Test func backoffDoublesAndCapsAt300Seconds() {
    #expect([0, 1, 2, 3, 8, 9, 20].map(OutboxProcessor.backoff) == [2, 2, 4, 8, 256, 300, 300])
  }

  @Test func successRemovesTheItem() async throws {
    let outbox = try makeOutbox()
    try await outbox.enqueueLog(payload(), now: now)
    let changed = try await outbox.run(now: now) { _, _ in }
    #expect(changed == ["2026-10-05"])
    #expect(try await outbox.items().isEmpty)
  }

  @Test func networkErrorKeepsTheItemAndBacksOff() async throws {
    let outbox = try makeOutbox()
    try await outbox.enqueueLog(payload(), now: now)
    try await outbox.run(now: now) { _, _ in throw URLError(.notConnectedToInternet) }
    var items = try await outbox.items()
    #expect(items.count == 1)
    #expect(items[0].attempts == 1)
    #expect(items[0].nextAttemptAt == now.addingTimeInterval(2))
    #expect(items[0].lastError == nil)

    // Not due yet: nothing runs.
    try await outbox.run(now: now.addingTimeInterval(1)) { _, _ in Issue.record("ran early") }
    try await outbox.run(now: now.addingTimeInterval(2)) { _, _ in
      throw URLError(.timedOut)
    }
    items = try await outbox.items()
    #expect(items[0].attempts == 2)
    #expect(items[0].nextAttemptAt == now.addingTimeInterval(6))
  }

  @Test func otherErrorsKeepTheItemWithLastError() async throws {
    struct ServerError: LocalizedError {
      var errorDescription: String? { "violates check constraint" }
    }
    let outbox = try makeOutbox()
    try await outbox.enqueueLog(payload(), now: now)
    try await outbox.run(now: now) { _, _ in throw ServerError() }
    let items = try await outbox.items()
    #expect(items.count == 1)
    #expect(items[0].lastError == "violates check constraint")
    #expect(items[0].logPayload != nil)
  }

  @Test func undoRemovesADelayedDeleteBeforeItRuns() async throws {
    let outbox = try makeOutbox()
    let entryId = UUID()
    let deleteId = try #require(
      try await outbox.enqueueDelete(entryId: entryId, date: key("2026-10-05"), now: now))
    let seen = Seen()
    try await outbox.run(now: now.addingTimeInterval(4)) { _, _ in await seen.append(UUID()) }
    #expect(await seen.ids.isEmpty)
    try await outbox.remove(id: deleteId)
    try await outbox.run(now: now.addingTimeInterval(10)) { _, _ in await seen.append(UUID()) }
    #expect(await seen.ids.isEmpty)
    #expect(try await outbox.items().isEmpty)
  }

  @Test func deletingAPendingEntryDropsItsLogItem() async throws {
    let outbox = try makeOutbox()
    let log = payload()
    try await outbox.enqueueLog(log, now: now)
    let result = try await outbox.enqueueDelete(
      entryId: log.entry.id, date: log.entry.date, now: now)
    #expect(result == nil)
    #expect(try await outbox.items().isEmpty)
  }

  @Test func runsInCreatedOrderAndStopsOnNetworkError() async throws {
    let outbox = try makeOutbox()
    let first = payload()
    let second = payload()
    try await outbox.enqueueLog(first, now: now)
    try await outbox.enqueueLog(second, now: now.addingTimeInterval(1))
    let seen = Seen()
    try await outbox.run(now: now.addingTimeInterval(5)) { _, data in
      let payload = try JSONDecoder.ezha.decode(LogPayload.self, from: data)
      await seen.append(payload.entry.id)
      throw URLError(.networkConnectionLost)
    }
    #expect(await seen.ids == [first.entry.id])
  }
}

actor Seen {
  var ids: [UUID] = []
  func append(_ id: UUID) { ids.append(id) }
}
