import Foundation
import SwiftData

/// One logger draft per date.
@Model
public final class LoggerDraft {
  @Attribute(.unique) public var dateKey: String
  public var state: Data
  @Attribute(.externalStorage) public var imageData: Data?
  /// Restaurant meals: the photo of what is left. Optional, so existing stores migrate as is.
  @Attribute(.externalStorage) public var leftoverImageData: Data?
  public var updatedAt: Date

  public init(
    dateKey: String, state: Data, imageData: Data?, leftoverImageData: Data? = nil,
    updatedAt: Date
  ) {
    self.dateKey = dateKey
    self.state = state
    self.imageData = imageData
    self.leftoverImageData = leftoverImageData
    self.updatedAt = updatedAt
  }
}

/// A saved logger draft: the state and its photos.
public struct LoggerDraftData: Sendable, Equatable {
  public var state: Data
  public var imageData: Data?
  public var leftoverImageData: Data?

  public init(state: Data, imageData: Data?, leftoverImageData: Data? = nil) {
    self.state = state
    self.imageData = imageData
    self.leftoverImageData = leftoverImageData
  }
}

@ModelActor
public actor DraftStore {
  public func load(_ date: DateKey) throws -> LoggerDraftData? {
    guard let draft = try fetch(date) else { return nil }
    return LoggerDraftData(
      state: draft.state, imageData: draft.imageData,
      leftoverImageData: draft.leftoverImageData)
  }

  public func save(
    _ date: DateKey, state: Data, imageData: Data?, leftoverImageData: Data? = nil,
    now: Date = .now
  ) throws {
    if let draft = try fetch(date) {
      draft.state = state
      draft.imageData = imageData
      draft.leftoverImageData = leftoverImageData
      draft.updatedAt = now
    } else {
      modelContext.insert(
        LoggerDraft(
          dateKey: date.rawValue, state: state, imageData: imageData,
          leftoverImageData: leftoverImageData, updatedAt: now))
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
