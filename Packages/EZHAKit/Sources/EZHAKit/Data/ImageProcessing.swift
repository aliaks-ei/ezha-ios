import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Port of the resize in `src/services/storage-service.ts`: longest side ≤ 1400 px,
/// JPEG quality 0.75. ImageIO thumbnails carry no metadata, so location data is dropped.
public enum ImageProcessing {
  public static let maxPixelSize = 1400
  public static let quality = 0.75

  public enum Failure: Error, LocalizedError {
    case unreadable
    public var errorDescription: String? { "This photo could not be read." }
  }

  /// Runs off the main actor.
  @concurrent
  public static func jpeg(from data: Data) async throws -> Data {
    try jpegSync(from: data)
  }

  static func jpegSync(from data: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      throw Failure.unreadable
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
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
      [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
    return output as Data
  }
}
