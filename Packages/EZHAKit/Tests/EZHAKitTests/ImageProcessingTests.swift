import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import EZHAKit

struct ImageProcessingTests {
  /// A 3000×2000 JPEG with a GPS location.
  func largePhotoWithLocation() throws -> Data {
    let context = try #require(
      CGContext(
        data: nil, width: 3000, height: 2000, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
    let output = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
    let gps: [CFString: Any] = [
      kCGImagePropertyGPSLatitude: 52.2, kCGImagePropertyGPSLatitudeRef: "N",
      kCGImagePropertyGPSLongitude: 21.0, kCGImagePropertyGPSLongitudeRef: "E",
    ]
    CGImageDestinationAddImage(
      destination, try #require(context.makeImage()),
      [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
  }

  func properties(_ data: Data) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
  }

  @Test func resizesToTheLongestSideAndStripsLocation() async throws {
    let original = try largePhotoWithLocation()
    #expect(try properties(original)[kCGImagePropertyGPSDictionary] != nil)

    let jpeg = try await ImageProcessing.jpeg(from: original)
    let props = try properties(jpeg)
    #expect(props[kCGImagePropertyPixelWidth] as? Int == 1400)
    #expect(props[kCGImagePropertyPixelHeight] as? Int == 933)
    #expect(props[kCGImagePropertyGPSDictionary] == nil)
  }

  @Test func rejectsData() async {
    await #expect(throws: ImageProcessing.Failure.self) {
      try await ImageProcessing.jpeg(from: Data("not an image".utf8))
    }
  }
}
