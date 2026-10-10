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

  /// The server bundle with pending logs added and pending deletes removed.
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
    return bundle
  }

  /// Count of pending entries in the merged day, for the footnote.
  func pendingCount(_ date: DateKey) -> Int {
    merged(date)?.entries.filter(\.isPending).count ?? 0
  }

  /// With no bundle for a date (offline, never loaded), use the goals of the latest cached day.
  private func fallbackBundle(_ date: DateKey) -> DayBundle? {
    guard !sync.pendingLogs(on: date).isEmpty,
      let latest = bundles.values.filter({ $0.date < date }).max(by: { $0.date < $1.date })
    else { return nil }
    return DayBundle(
      date: date, target: latest.target, goals: latest.goals, totals: .zero,
      targets: latest.targets, entries: [])
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
