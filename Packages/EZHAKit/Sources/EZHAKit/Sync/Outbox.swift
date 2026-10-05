import Foundation
import SwiftData

/// A queued write. Kinds: `logEntry` (payload = `LogPayload`), `deleteEntry` (payload = entry id).
@Model
public final class PendingMutation {
  @Attribute(.unique) public var id: UUID
  public var kind: String
  public var payload: Data
  /// The entry this mutation is about, to find it for undo and pending deletes.
  public var entityId: UUID
  /// The entry's date, so pending rows merge into the right day.
  public var dateKey: String
  public var attempts: Int
  public var nextAttemptAt: Date
  public var lastError: String?
  public var createdAt: Date

  public init(
    id: UUID = UUID(), kind: Kind, payload: Data, entityId: UUID, dateKey: String,
    nextAttemptAt: Date, createdAt: Date
  ) {
    self.id = id
    self.kind = kind.rawValue
    self.payload = payload
    self.entityId = entityId
    self.dateKey = dateKey
    self.attempts = 0
    self.nextAttemptAt = nextAttemptAt
    self.lastError = nil
    self.createdAt = createdAt
  }

  public enum Kind: String, Sendable, Codable {
    case logEntry
    case deleteEntry
  }
}

/// A value copy of a `PendingMutation` for the UI.
public struct PendingItem: Sendable, Hashable, Identifiable {
  public var id: UUID
  public var kind: PendingMutation.Kind
  public var entityId: UUID
  public var date: DateKey?
  public var attempts: Int
  public var nextAttemptAt: Date
  public var lastError: String?
  public var createdAt: Date
  /// The entry to show as a pending row, for `logEntry`.
  public var logPayload: LogPayload?
}

/// Runs the outbox one item at a time in `createdAt` order.
@ModelActor
public actor OutboxProcessor {
  public typealias Perform = @Sendable (PendingMutation.Kind, Data) async throws -> Void

  /// `min(2^max(1, attempts) s, 300 s)`, like `retry-queue-service.ts`.
  public static func backoff(attempts: Int) -> TimeInterval {
    min(pow(2, Double(max(1, attempts))), 300)
  }

  public func enqueueLog(_ payload: LogPayload, now: Date = .now) throws {
    let data = try JSONEncoder.ezha.encode(payload)
    modelContext.insert(
      PendingMutation(
        kind: .logEntry, payload: data, entityId: payload.entry.id,
        dateKey: payload.entry.date.rawValue, nextAttemptAt: now, createdAt: now))
    try modelContext.save()
  }

  /// Queues a delete that runs after `delay`, so it can be undone.
  /// Deleting an entry that is still waiting to be logged removes its `logEntry` item instead.
  /// Returns the id of the queued delete, or nil when a pending log was dropped.
  @discardableResult
  public func enqueueDelete(entryId: UUID, date: DateKey, delay: TimeInterval = 5, now: Date = .now)
    throws -> UUID?
  {
    if let pending = try mutations(kind: .logEntry, entityId: entryId).first {
      modelContext.delete(pending)
      try modelContext.save()
      return nil
    }
    let mutation = PendingMutation(
      kind: .deleteEntry, payload: Data(entryId.uuidString.utf8), entityId: entryId,
      dateKey: date.rawValue, nextAttemptAt: now.addingTimeInterval(delay), createdAt: now)
    modelContext.insert(mutation)
    try modelContext.save()
    return mutation.id
  }

  public func remove(id: UUID) throws {
    for mutation in try modelContext.fetch(
      FetchDescriptor<PendingMutation>(predicate: #Predicate { $0.id == id }))
    {
      modelContext.delete(mutation)
    }
    try modelContext.save()
  }

  /// Makes every item due now, for "Retry now".
  public func makeAllDue(now: Date = .now) throws {
    for mutation in try modelContext.fetch(FetchDescriptor<PendingMutation>()) {
      mutation.nextAttemptAt = now
    }
    try modelContext.save()
  }

  public func items() throws -> [PendingItem] {
    let descriptor = FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.createdAt)])
    return try modelContext.fetch(descriptor).map { mutation in
      let kind = PendingMutation.Kind(rawValue: mutation.kind) ?? .logEntry
      return PendingItem(
        id: mutation.id, kind: kind, entityId: mutation.entityId,
        date: DateKey(mutation.dateKey), attempts: mutation.attempts,
        nextAttemptAt: mutation.nextAttemptAt, lastError: mutation.lastError,
        createdAt: mutation.createdAt,
        logPayload: kind == .logEntry
          ? try? JSONDecoder.ezha.decode(LogPayload.self, from: mutation.payload) : nil)
    }
  }

  /// Runs every due item. Success removes it. A network error backs off and stops the run.
  /// Any other error keeps the item with `lastError` and backs off. Returns the dates that changed.
  @discardableResult
  public func run(now: Date = .now, perform: Perform) async throws -> Set<String> {
    var changed: Set<String> = []
    let descriptor = FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.createdAt)])
    for mutation in try modelContext.fetch(descriptor) where mutation.nextAttemptAt <= now {
      guard let kind = PendingMutation.Kind(rawValue: mutation.kind) else { continue }
      do {
        try await perform(kind, mutation.payload)
        changed.insert(mutation.dateKey)
        modelContext.delete(mutation)
        try modelContext.save()
      } catch {
        mutation.attempts += 1
        mutation.nextAttemptAt = now.addingTimeInterval(Self.backoff(attempts: mutation.attempts))
        if isNetworkError(error) {
          mutation.lastError = nil
          try modelContext.save()
          break
        }
        mutation.lastError = error.localizedDescription
        try modelContext.save()
      }
    }
    return changed
  }

  private func mutations(kind: PendingMutation.Kind, entityId: UUID) throws -> [PendingMutation] {
    let raw = kind.rawValue
    return try modelContext.fetch(
      FetchDescriptor<PendingMutation>(
        predicate: #Predicate { $0.kind == raw && $0.entityId == entityId }))
  }
}
