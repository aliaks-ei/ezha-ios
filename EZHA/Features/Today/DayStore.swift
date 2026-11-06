import EZHAKit
import Foundation
import Observation
import WidgetKit

/// Day bundles per date: cached first, then fetched. Pending outbox entries merge in.
@MainActor
@Observable
final class DayStore {
  enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
  }

  enum LogResult: Equatable {
    case saved
    case queued
  }

  private(set) var bundles: [DateKey: DayBundle] = [:]
  private(set) var states: [DateKey: LoadState] = [:]

  @ObservationIgnored private let clients: AppClients
  @ObservationIgnored private let cache: FileCache
  @ObservationIgnored private let sync: SyncEngine
  @ObservationIgnored var today: () -> DateKey = { .today() }
  /// Called after each log is queued or saved.
  @ObservationIgnored var onLogged: (@MainActor () -> Void)?

  init(clients: AppClients, cache: FileCache, sync: SyncEngine) {
    self.clients = clients
    self.cache = cache
    self.sync = sync
  }

  func state(for date: DateKey) -> LoadState { states[date] ?? .idle }

  /// The server bundle with pending logs and water added, and pending deletes removed.
  func merged(_ date: DateKey) -> DayBundle? {
    guard var bundle = bundles[date] ?? fallbackBundle(date) else { return nil }
    let deleted = sync.pendingDeletes()
    let serverIds = Set(bundle.entries.map(\.id))
    let pending = sync.pendingLogs(on: date)
      .filter { !serverIds.contains($0.entry.id) }
      .map { DayEntry(entry: $0.entry, items: $0.items, isPending: true) }
    bundle.entries = (pending + bundle.entries.filter { !deleted.contains($0.id) })
      .sorted { ($0.entry.createdAt ?? .distantPast) > ($1.entry.createdAt ?? .distantPast) }
    bundle.totals = Macros.dayTotals(bundle.entries.map(\.entry))
    bundle.water = mergedWater(bundle.water, on: date)
    return bundle
  }

  /// Queued saves replace their server row (an edit) or add a row. Queued deletes hide it.
  private func mergedWater(_ water: [WaterEntry], on date: DateKey) -> [WaterEntry] {
    let deleted = sync.pendingWaterDeletes()
    let pending = sync.pendingWater(on: date).map { entry in
      var entry = entry
      entry.isPending = true
      return entry
    }
    let pendingIds = Set(pending.map(\.id))
    return (pending + water.filter { !pendingIds.contains($0.id) })
      .filter { !deleted.contains($0.id) }
      .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
  }

  /// Count of pending entries in the merged day, for the footnote.
  func pendingCount(_ date: DateKey) -> Int {
    merged(date)?.entries.filter(\.isPending).count ?? 0
  }

  /// With no bundle for a date (offline, never loaded), use the goals of the latest cached day.
  private func fallbackBundle(_ date: DateKey) -> DayBundle? {
    guard !sync.pendingLogs(on: date).isEmpty || !sync.pendingWater(on: date).isEmpty,
      let latest = bundles.values.filter({ $0.date < date }).max(by: { $0.date < $1.date })
    else { return nil }
    return DayBundle(
      date: date, target: latest.target, goals: latest.goals, totals: .zero,
      targets: latest.targets, entries: [], waterTargetMl: latest.waterTargetMl)
  }

  /// Shows the cached bundle at once, then fetches and writes the cache.
  func load(_ date: DateKey, force: Bool = false) async {
    if bundles[date] == nil, let cached: DayBundle = await cache.read(FileCache.dayKey(date)) {
      bundles[date] = cached
    }
    if !force, states[date] == .loading { return }
    states[date] = .loading
    do {
      let bundle = try await clients.day.fetchDay(date)
      bundles[date] = bundle
      states[date] = .loaded
      await cache.write(bundle, for: FileCache.dayKey(date))
      if !bundle.targets.isEmpty { await cache.write(bundle.targets, for: "targets") }
    } catch is CancellationError {
      states[date] = .idle
    } catch {
      states[date] = .failed(error.localizedDescription)
    }
    updateSnapshot(date)
  }

  /// Logs through the outbox, so the pending row shows at once and any failure keeps the entry
  /// queued (network errors retry; other errors show in Settings › Sync).
  func log(_ payload: LogPayload) async throws -> LogResult {
    try await sync.enqueueLog(payload)
    onLogged?()
    if sync.items.contains(where: { $0.entityId == payload.entry.id }) {
      updateSnapshot(payload.entry.date)
      return .queued
    }
    await load(payload.entry.date, force: true)
    return .saved
  }

  /// Hides the row and queues the delete for after the undo toast. Returns the undo action.
  func delete(_ entry: DayEntry) async -> (@MainActor () async -> Void)? {
    let date = entry.entry.date
    do {
      let window = ToastMessage.undoWindow.components
      let outboxId = try await sync.enqueueDelete(
        entryId: entry.id, date: date, delay: Double(window.seconds) + 0.5)
      updateSnapshot(date)
      if let outboxId {
        return { [weak self] in
          await self?.sync.remove(id: outboxId)
          self?.updateSnapshot(date)
        }
      }
      // A pending log was dropped. Undo queues it again.
      let payload = LogPayload(
        entry: entry.entry, items: entry.items, usedFoodIds: [])
      return { [weak self] in _ = try? await self?.log(payload) }
    } catch {
      return nil
    }
  }

  // MARK: Water

  /// Adds water through the outbox, so it shows at once and syncs later when offline.
  /// Returns the undo action.
  func addWater(_ entry: WaterEntry) async throws -> @MainActor () async -> Void {
    try await sync.enqueueSaveWater(entry)
    return { [weak self] in _ = await self?.deleteWater(entry, delay: 0) }
  }

  /// Creates or edits an entry. An edit of an entry that waits to sync replaces the queued save.
  func saveWater(_ entry: WaterEntry) async throws {
    try await sync.enqueueSaveWater(entry)
  }

  /// Hides the entry and deletes it after `delay`. Returns the undo action.
  func deleteWater(_ entry: WaterEntry, delay: TimeInterval) async -> (@MainActor () async -> Void)?
  {
    do {
      let outboxId = try await sync.enqueueDeleteWater(
        entryId: entry.id, date: entry.date, delay: delay)
      if let outboxId {
        return { [weak self] in await self?.sync.remove(id: outboxId) }
      }
      // A pending save was dropped. Undo queues it again.
      var copy = entry
      copy.isPending = false
      return { [weak self] in try? await self?.saveWater(copy) }
    } catch {
      return nil
    }
  }

  /// Deletes after the undo toast, like a meal.
  func deleteWaterWithUndo(_ entry: WaterEntry) async -> (@MainActor () async -> Void)? {
    let window = ToastMessage.undoWindow.components
    return await deleteWater(entry, delay: Double(window.seconds) + 0.5)
  }

  func setTarget(_ targetId: UUID, for date: DateKey) async throws {
    try await clients.day.setTarget(date, targetId, today())
    await load(date, force: true)
  }

  /// Drops cached bundles of other days after a target change, so they refetch.
  func invalidate(except date: DateKey? = nil) {
    for key in bundles.keys where key != date { states[key] = .idle }
  }

  /// Writes the widget snapshot for today and reloads widgets.
  func updateSnapshot(_ date: DateKey) {
    guard date == today(), let bundle = merged(date) else { return }
    SnapshotStore.write(
      WidgetSnapshot(
        date: date, targetName: bundle.target?.name, goals: bundle.goals, totals: bundle.totals,
        updatedAt: .now))
    WidgetCenter.shared.reloadAllTimelines()
  }

  func clear() {
    bundles = [:]
    states = [:]
  }
}
