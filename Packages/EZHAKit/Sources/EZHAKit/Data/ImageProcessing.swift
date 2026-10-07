import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Meal photos retain the established size; label scans preserve more readable text.
/// ImageIO thumbnails carry no metadata, so location data is dropped.
public enum ImageProcessing {
  public static let maxPixelSize = 1400
  public static let labelMaxPixelSize = 1800
  public static let quality = 0.75

  public enum Failure: Error, LocalizedError {
    case unreadable
    public var errorDescription: String? { "This photo could not be read." }
  }

  /// Runs off the main actor.
  @concurrent
  public static func jpeg(from data: Data, forLabel: Bool = false) async throws -> Data {
    try jpegSync(from: data, forLabel: forLabel)
  }

  static func jpegSync(from data: Data, forLabel: Bool = false) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      throw Failure.unreadable
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: forLabel ? labelMaxPixelSize : maxPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { throw Failure.unreadable }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.jpeg.identifier as CFString, 1, nil)
    else { throw Failure.unreadable }
    CGImageDestinationAddImage(
      destination, image,
      [kCGImageDestinationLossyCompressionQuality: forLabel ? 0.85 : quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
    return output as Data
  }
}
