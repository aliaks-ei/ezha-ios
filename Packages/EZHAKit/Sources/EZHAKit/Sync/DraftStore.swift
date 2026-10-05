import Foundation
import SwiftData

/// One logger draft per date.
@Model
public final class LoggerDraft {
  @Attribute(.unique) public var dateKey: String
  public var state: Data
  @Attribute(.externalStorage) public var imageData: Data?
  public var updatedAt: Date

  public init(dateKey: String, state: Data, imageData: Data?, updatedAt: Date) {
    self.dateKey = dateKey
    self.state = state
    self.imageData = imageData
    self.updatedAt = updatedAt
  }
}

@ModelActor
public actor DraftStore {
  public func load(_ date: DateKey) throws -> (state: Data, imageData: Data?)? {
    guard let draft = try fetch(date) else { return nil }
    return (draft.state, draft.imageData)
  }

  public func save(_ date: DateKey, state: Data, imageData: Data?, now: Date = .now) throws {
    if let draft = try fetch(date) {
      draft.state = state
      draft.imageData = imageData
      draft.updatedAt = now
    } else {
      modelContext.insert(
        LoggerDraft(dateKey: date.rawValue, state: state, imageData: imageData, updatedAt: now))
    }
    try modelContext.save()
  }

  public func delete(_ date: DateKey) throws {
    if let draft = try fetch(date) {
      modelContext.delete(draft)
      try modelContext.save()
    }
  }

  public func deleteAll() throws {
    try modelContext.delete(model: LoggerDraft.self)
    try modelContext.save()
  }

  private func fetch(_ date: DateKey) throws -> LoggerDraft? {
    let raw = date.rawValue
    return try modelContext.fetch(
      FetchDescriptor<LoggerDraft>(predicate: #Predicate { $0.dateKey == raw })
    ).first
  }
}

/// The SwiftData container for the outbox and drafts.
public enum LocalStore {
  public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
    let schema = Schema([PendingMutation.self, LoggerDraft.self])
    return try ModelContainer(
      for: schema,
      configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory))
  }
}
