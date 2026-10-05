import Foundation
import Network
import Observation

/// `NWPathMonitor` as an observable `isOnline` flag.
@MainActor
@Observable
public final class NetworkMonitor {
  public private(set) var isOnline = true
  @ObservationIgnored private let monitor = NWPathMonitor()
  /// Called when the network becomes reachable again.
  @ObservationIgnored public var onReconnect: (@MainActor () -> Void)?

  public init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let online = path.status == .satisfied
      Task { @MainActor in self?.update(online) }
    }
    monitor.start(queue: DispatchQueue(label: "ezha.network-monitor"))
  }

  private func update(_ online: Bool) {
    let reconnected = online && !isOnline
    isOnline = online
    if reconnected { onReconnect?() }
  }
}

/// Network failures that keep an outbox item for a later retry.
public func isNetworkError(_ error: any Error) -> Bool {
  let codes: Set<URLError.Code> = [
    .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
    .cannotConnectToHost,
  ]
  if let urlError = error as? URLError { return codes.contains(urlError.code) }
  let nsError = error as NSError
  if nsError.domain == NSURLErrorDomain {
    return codes.contains(URLError.Code(rawValue: nsError.code))
  }
  if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? any Error {
    return isNetworkError(underlying)
  }
  return false
}
