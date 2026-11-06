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

struct WaterOutboxTests {
  let now = Date(timeIntervalSince1970: 1_000_000)
  let date = key("2026-10-07")

  func makeOutbox() throws -> OutboxProcessor {
    OutboxProcessor(modelContainer: try LocalStore.makeContainer(inMemory: true))
  }

  @Test func saveWaterQueuesTheEntryForTheDay() async throws {
    let outbox = try makeOutbox()
    let entry = WaterEntry(date: date, amountMl: 250, createdAt: now)
    try await outbox.enqueueSaveWater(entry, now: now)
    let items = try await outbox.items()
    #expect(items.count == 1)
    #expect(items[0].kind == .saveWater)
    #expect(items[0].date == date)
    #expect(items[0].waterEntry?.amountMl == 250)
    let changed = try await outbox.run(now: now) { kind, data in
      let sent = try JSONDecoder.ezha.decode(WaterEntry.self, from: data)
      #expect(kind == .saveWater)
      #expect(sent.id == entry.id)
    }
    #expect(changed == ["2026-10-07"])
    #expect(try await outbox.items().isEmpty)
  }

  @Test func editingAPendingEntryReplacesItsQueuedSave() async throws {
    let outbox = try makeOutbox()
    var entry = WaterEntry(date: date, amountMl: 250, createdAt: now)
    try await outbox.enqueueSaveWater(entry, now: now)
    entry.amountMl = 330
    try await outbox.enqueueSaveWater(entry, now: now.addingTimeInterval(1))
    let items = try await outbox.items()
    #expect(items.count == 1)
    #expect(items[0].waterEntry?.amountMl == 330)
  }

  @Test func deletingAPendingWaterEntryDropsItsSave() async throws {
    let outbox = try makeOutbox()
    let entry = WaterEntry(date: date, amountMl: 250, createdAt: now)
    try await outbox.enqueueSaveWater(entry, now: now)
    let result = try await outbox.enqueueDeleteWater(entryId: entry.id, date: date, now: now)
    #expect(result == nil)
    #expect(try await outbox.items().isEmpty)
  }

  @Test func deletingASyncedWaterEntryWaitsForUndo() async throws {
    let outbox = try makeOutbox()
    let id = UUID()
    let deleteId = try #require(
      try await outbox.enqueueDeleteWater(entryId: id, date: date, delay: 5, now: now))
    let seen = Seen()
    try await outbox.run(now: now.addingTimeInterval(4)) { _, _ in await seen.append(UUID()) }
    #expect(await seen.ids.isEmpty)
    try await outbox.run(now: now.addingTimeInterval(6)) { kind, data in
      #expect(kind == .deleteWater)
      await seen.append(UUID(uuidString: String(decoding: data, as: UTF8.self))!)
    }
    #expect(await seen.ids == [id])
    _ = deleteId
  }

  @Test func anEditDuringASendIsQueuedAgain() async throws {
    let outbox = try makeOutbox()
    var entry = WaterEntry(date: date, amountMl: 250, createdAt: now)
    try await outbox.enqueueSaveWater(entry, now: now)
    entry.amountMl = 500
    let edited = entry
    let seen = Seen()
    try await outbox.run(now: now) { _, data in
      // The user edits the entry while the first save is on its way.
      try await outbox.enqueueSaveWater(edited, now: now)
      let sent = try JSONDecoder.ezha.decode(WaterEntry.self, from: data)
      await seen.append(sent.id)
    }
    let items = try await outbox.items()
    #expect(items.count == 1)
    #expect(items[0].waterEntry?.amountMl == 500)
  }

  @Test func aDeleteDuringASendIsQueuedAfterIt() async throws {
    let outbox = try makeOutbox()
    let entry = WaterEntry(date: date, amountMl: 250, createdAt: now)
    try await outbox.enqueueSaveWater(entry, now: now)
    try await outbox.run(now: now) { _, _ in
      // Undo while the save is on its way: the server may already have it, so delete it there.
      let id = try await outbox.enqueueDeleteWater(
        entryId: entry.id, date: entry.date, delay: 0, now: now)
      #expect(id != nil)
    }
    let items = try await outbox.items()
    #expect(items.map(\.kind) == [.deleteWater])
  }
}

actor Seen {
  var ids: [UUID] = []
  func append(_ id: UUID) { ids.append(id) }
}
