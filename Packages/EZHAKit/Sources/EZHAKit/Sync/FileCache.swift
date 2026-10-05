import Foundation

/// Last-seen server data as JSON files in `Caches/`. Keys: `day-<date>`, `library`, `targets`.
public actor FileCache {
  private let directory: URL

  public init(directory: URL? = nil) {
    self.directory =
      directory
      ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appending(path: "ezha-cache", directoryHint: .isDirectory)
  }

  public static func dayKey(_ date: DateKey) -> String { "day-\(date.rawValue)" }

  public func read<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
    guard let data = try? Data(contentsOf: url(key)) else { return nil }
    return try? JSONDecoder.ezha.decode(T.self, from: data)
  }

  public func write(_ value: some Encodable, for key: String) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try JSONEncoder.ezha.encode(value).write(to: url(key), options: .atomic)
    } catch {
      // A cache write failure only costs a slower next launch.
    }
  }

  /// Removes everything, for sign-out.
  public func clear() {
    try? FileManager.default.removeItem(at: directory)
  }

  private func url(_ key: String) -> URL {
    directory.appending(path: "\(key).json")
  }
}
