import AVFoundation
import CoreImage
import Foundation

/// Analyzes color composition and dominant colors in video frames.
class ColorAnalyzer: VideoReaderObserver {
  private let videoAnalyzer: VideoAnalyzer
  var videoInterval: Int { 15 } // Process twice per second (at 30fps)

  var results: [(timestamp: Double, dominantColors: [CIColor], palette: [String: Double])] = []

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
  }

  func processFrame(_ result: FrameResult) {
    let ciImage = CIImage(cvPixelBuffer: result.pixelBuffer)
    let timestamp = result.timestamp

    let dominantColors = extractDominantColors(from: ciImage)
    let palette = createColorPalette(from: result.pixelBuffer)

    results.append((
      timestamp: timestamp,
      dominantColors: dominantColors,
      palette: palette
    ))
  }

  private func extractDominantColors(from image: CIImage) -> [CIColor] {
    let extent = image.extent
    let samplePoints = [
      CIVector(x: extent.midX, y: extent.midY),
      CIVector(x: extent.minX + extent.width * 0.25, y: extent.midY),
      CIVector(x: extent.maxX - extent.width * 0.25, y: extent.midY),
      CIVector(x: extent.midX, y: extent.minY + extent.height * 0.25),
      CIVector(x: extent.midX, y: extent.maxY - extent.height * 0.25)
    ]

    var colors = [CIColor]()
    let context = CIContext()

    for point in samplePoints {
      let filter = CIFilter(name: "CIAreaAverage", parameters: [
        kCIInputImageKey: image,
        kCIInputExtentKey: CIVector(x: point.x, y: point.y, z: 1, w: 1)
      ])

      if let outputImage = filter?.outputImage,
         let color = extractColor(from: outputImage, context: context) {
        colors.append(color)
      }
    }

    return Array(Set(colors)).prefix(5).map { $0 }
  }

  private func createColorPalette(from pixelBuffer: CVPixelBuffer) -> [String: Double] {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    var colorCounts = [String: Int]()

    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
      let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
      let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

      for y in stride(from: 0, to: height, by: max(1, height / 20)) {
        for x in stride(from: 0, to: width, by: max(1, width / 20)) {
          let offset = y * bytesPerRow + x * 4
          let r = Int(buffer[offset + 2])
          let g = Int(buffer[offset + 1])
          let b = Int(buffer[offset])

          let quantizedR = (r / 32) * 32
          let quantizedG = (g / 32) * 32
          let quantizedB = (b / 32) * 32

          let colorKey = String(format: "%02X%02X%02X", quantizedR, quantizedG, quantizedB)
          colorCounts[colorKey, default: 0] += 1
        }
      }
    }

    let totalPixels = colorCounts.values.reduce(0, +)
    var palette = [String: Double]()
    for (color, count) in colorCounts.sorted(by: { $0.value > $1.value }).prefix(10) {
      palette[color] = Double(count) / Double(totalPixels) * 100
    }

    return palette
  }

  private func extractColor(from image: CIImage, context: CIContext) -> CIColor? {
    let extent = image.extent
    guard let cgImage = context.createCGImage(image, from: extent) else { return nil }
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixelData = [UInt8](repeating: 0, count: 4)

    guard let context2 = CGContext(
      data: &pixelData,
      width: 1, height: 1,
      bitsPerComponent: 8, bytesPerRow: 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    context2.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

    return CIColor(red: CGFloat(pixelData[0]) / 255.0,
                   green: CGFloat(pixelData[1]) / 255.0,
                   blue: CGFloat(pixelData[2]) / 255.0,
                   alpha: CGFloat(pixelData[3]) / 255.0)
  }
}
