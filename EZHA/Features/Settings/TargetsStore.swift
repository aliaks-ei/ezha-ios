import EZHAKit
import Foundation
import Observation

/// Daily targets: cached first, then fetched. Changes are online only.
@MainActor
@Observable
final class TargetsStore {
  private(set) var targets: [DailyTarget] = []
  private(set) var errorMessage: String?
  private(set) var isLoading = false

  @ObservationIgnored private let clients: AppClients
  @ObservationIgnored private let cache: FileCache
  @ObservationIgnored var today: () -> DateKey = { .today() }
  /// Called after a change, so day bundles refetch.
  @ObservationIgnored var onChange: (@MainActor () async -> Void)?

  init(clients: AppClients, cache: FileCache) {
    self.clients = clients
    self.cache = cache
  }

  func load() async {
    if targets.isEmpty, let cached: [DailyTarget] = await cache.read("targets") {
      targets = cached
    }
    isLoading = true
    defer { isLoading = false }
    do {
      targets = try await clients.targets.list()
      errorMessage = nil
      await cache.write(targets, for: "targets")
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @discardableResult
  func save(id: UUID?, name: String, macros: MacroTotals) async throws -> UUID {
    let newId = try await clients.targets.save(id, name, macros, today())
    await load()
    await onChange?()
    return newId
  }

  func delete(_ target: DailyTarget) async throws {
    try await clients.targets.delete(target.id, today())
    await load()
    await onChange?()
  }

  func clear() {
    targets = []
  }
}
