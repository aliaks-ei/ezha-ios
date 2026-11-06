import EZHAKit
import Foundation
import Observation
import SwiftData

/// Runs the outbox: on launch, when the app becomes active, when the network comes back,
/// after each enqueue, and when the next backoff is due.
@MainActor
@Observable
final class SyncEngine {
  private(set) var items: [PendingItem] = []
  private(set) var isRunning = false
  let network = NetworkMonitor()
  /// Called with the dates whose server data changed.
  @ObservationIgnored var onSynced: (@MainActor (Set<DateKey>) async -> Void)?

  @ObservationIgnored private let processor: OutboxProcessor
  @ObservationIgnored private let drafts: DraftStore
  @ObservationIgnored private let clients: AppClients
  @ObservationIgnored private var wakeTask: Task<Void, Never>?

  init(container: ModelContainer, clients: AppClients) {
    processor = OutboxProcessor(modelContainer: container)
    drafts = DraftStore(modelContainer: container)
    self.clients = clients
    network.onReconnect = { [weak self] in Task { await self?.run() } }
  }

  var draftStore: DraftStore { drafts }

  func pendingLogs(on date: DateKey) -> [LogPayload] {
    items.filter { $0.kind == .logEntry && $0.date == date }.compactMap(\.logPayload)
  }

  func pendingDeletes() -> Set<UUID> {
    Set(items.filter { $0.kind == .deleteEntry }.map(\.entityId))
  }

  /// Water entries created or edited on this device and not synced yet.
  func pendingWater(on date: DateKey) -> [WaterEntry] {
    items.filter { $0.kind == .saveWater && $0.date == date }.compactMap(\.waterEntry)
  }

  func pendingWaterDeletes() -> Set<UUID> {
    Set(items.filter { $0.kind == .deleteWater }.map(\.entityId))
  }

  func enqueueSaveWater(_ entry: WaterEntry) async throws {
    try await processor.enqueueSaveWater(entry)
    await refresh()
    await run()
  }

  /// Queues a water delete after `delay`. Returns the outbox id for undo, or nil when a pending
  /// save was dropped.
  func enqueueDeleteWater(entryId: UUID, date: DateKey, delay: TimeInterval) async throws -> UUID? {
    let id = try await processor.enqueueDeleteWater(entryId: entryId, date: date, delay: delay)
    await refresh()
    if delay <= 0 { await run() } else { scheduleWake() }
    return id
  }

  func refresh() async {
    items = (try? await processor.items()) ?? items
  }

  func enqueueLog(_ payload: LogPayload) async throws {
    try await processor.enqueueLog(payload)
    await refresh()
    await run()
  }

  /// Queues a delete in 5 s. Returns the outbox id for undo, or nil when a pending log was dropped.
  func enqueueDelete(entryId: UUID, date: DateKey, delay: TimeInterval = 5) async throws -> UUID? {
    let id = try await processor.enqueueDelete(entryId: entryId, date: date, delay: delay)
    await refresh()
    scheduleWake()
    return id
  }

  func remove(id: UUID) async {
    try? await processor.remove(id: id)
    await refresh()
  }

  func retryNow() async {
    try? await processor.makeAllDue()
    await run()
  }

  func run() async {
    guard !isRunning else { return }
    isRunning = true
    let clients = clients
    let changed = try? await processor.run { kind, data in
      switch kind {
      case .logEntry:
        try await clients.logging.logEntry(JSONDecoder.ezha.decode(LogPayload.self, from: data))
      case .deleteEntry:
        guard let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) else { return }
        try await clients.day.deleteEntry(id)
      case .saveWater:
        try await clients.day.saveWater(JSONDecoder.ezha.decode(WaterEntry.self, from: data))
      case .deleteWater:
        guard let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) else { return }
        try await clients.day.deleteWater(id)
      }
    }
    isRunning = false
    await refresh()
    if let changed, !changed.isEmpty {
      await onSynced?(Set(changed.compactMap { DateKey($0) }))
    }
    scheduleWake()
  }

  /// Wakes at the next due item. Only one wake is pending at a time.
  private func scheduleWake() {
    wakeTask?.cancel()
    guard let next = items.map(\.nextAttemptAt).min() else { return }
    let delay = max(0.5, next.timeIntervalSinceNow + 0.2)
    wakeTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      await self?.run()
    }
  }

  /// Removes queued writes and drafts, for sign-out.
  func clearAll() async {
    for item in items { try? await processor.remove(id: item.id) }
    try? await drafts.deleteAll()
    await refresh()
  }
}
