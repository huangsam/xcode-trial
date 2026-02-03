import AVFoundation
import CoreImage
import Foundation

class SceneDetector {
  private let videoAnalyzer: VideoAnalyzer

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
  }

  func detectSceneBoundaries() -> [(timestamp: Double, type: String, confidence: Double)] {
    print("🎬 Performing advanced scene detection...")

    guard let videoTrack = videoAnalyzer.videoTrack else { return [] }

    let reader = try? AVAssetReader(asset: videoAnalyzer.asset)
    let outputSettings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
    reader?.add(trackOutput)

    guard reader?.startReading() == true else { return [] }

    var sceneBoundaries: [(timestamp: Double, type: String, confidence: Double)] = []
    var frameCount = 0
    var previousFrameData: [UInt8]?
    var previousHistogram: [Int]?

    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
      frameCount += 1

      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

      let frameData = videoAnalyzer.extractFrameData(from: pixelBuffer)
      let histogram = calculateHistogram(from: pixelBuffer)
      let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

      // Multiple scene detection methods
      if let previous = previousFrameData, let prevHist = previousHistogram {
        let pixelDifference = videoAnalyzer.calculateFrameDifference(previous, frameData)
        let histogramDifference = calculateHistogramDifference(prevHist, histogram)

        // Hard cut detection (sudden change)
        if pixelDifference > 0.3 && histogramDifference > 0.4 {
          sceneBoundaries.append(
            (
              timestamp: timestamp, type: "hard_cut",
              confidence: min(pixelDifference, histogramDifference)
            ))
        }
        // Fade detection (gradual brightness change)
        else if detectFade(pixelBuffer, previousFrame: previous) {
          sceneBoundaries.append((timestamp: timestamp, type: "fade", confidence: 0.7))
        }
        // Dissolve detection (gradual pixel change)
        else if pixelDifference > 0.15 && histogramDifference < 0.2 {
          sceneBoundaries.append(
            (timestamp: timestamp, type: "dissolve", confidence: pixelDifference))
        }
      }

      previousFrameData = frameData
      previousHistogram = histogram

      if frameCount >= 1000 { break }  // Demo limit
    }

    reader?.cancelReading()

    print("  ✅ Detected \(sceneBoundaries.count) scene boundaries")
    let cutCount = sceneBoundaries.filter { $0.type == "hard_cut" }.count
    let fadeCount = sceneBoundaries.filter { $0.type == "fade" }.count
    let dissolveCount = sceneBoundaries.filter { $0.type == "dissolve" }.count

    print("  ✂️  Hard cuts: \(cutCount)")
    print("  🌅 Fades: \(fadeCount)")
    print("  🔄 Dissolves: \(dissolveCount)")

    analyzeSceneLengths(sceneBoundaries)

    return sceneBoundaries
  }

  private func calculateHistogram(from pixelBuffer: CVPixelBuffer) -> [Int] {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    var histogram = [Int](repeating: 0, count: 256)

    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
      let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
      let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

      for y in stride(from: 0, to: height, by: max(1, height / 20)) {
        for x in stride(from: 0, to: width, by: max(1, width / 20)) {
          let offset = y * bytesPerRow + x * 4
          if offset < bytesPerRow * height {
            let r = Int(buffer[offset + 2])
            let g = Int(buffer[offset + 1])
            let b = Int(buffer[offset])
            let brightness = (r + g + b) / 3
            histogram[brightness] += 1
          }
        }
      }
    }

    return histogram
  }

  private func calculateHistogramDifference(_ hist1: [Int], _ hist2: [Int]) -> Double {
    var totalDiff = 0
    let totalPixels = hist1.reduce(0, +)

    for i in 0..<min(hist1.count, hist2.count) {
      totalDiff += abs(hist1[i] - hist2[i])
    }

    return Double(totalDiff) / Double(totalPixels)
  }

  private func detectFade(_ currentFrame: CVPixelBuffer, previousFrame: [UInt8]) -> Bool {
    // Simple fade detection based on brightness consistency
    let currentBrightness = calculateAverageBrightness(from: currentFrame)

    guard !previousFrame.isEmpty else { return false }

    let previousBrightness =
      Double(previousFrame.reduce(0, { $0 + Int($1) })) / Double(previousFrame.count)

    // Fade detected if brightness is very similar (within 5%)
    return abs(currentBrightness - previousBrightness) < 0.05
  }

  private func calculateAverageBrightness(from pixelBuffer: CVPixelBuffer) -> Double {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    var totalBrightness = 0.0
    var pixelCount = 0

    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
      let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
      let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

      for y in stride(from: 0, to: height, by: max(1, height / 20)) {
        for x in stride(from: 0, to: width, by: max(1, width / 20)) {
          let offset = y * bytesPerRow + x * 4
          if offset < bytesPerRow * height {
            let r = Int(buffer[offset + 2])
            let g = Int(buffer[offset + 1])
            let b = Int(buffer[offset])
            totalBrightness += Double((r + g + b) / 3)
            pixelCount += 1
          }
        }
      }
    }

    return pixelCount > 0 ? totalBrightness / Double(pixelCount) / 255.0 : 0.0
  }

  private func analyzeSceneLengths(
    _ boundaries: [(timestamp: Double, type: String, confidence: Double)]
  ) {
    if boundaries.isEmpty { return }

    var sceneLengths: [Double] = []
    var previousTimestamp = 0.0

    for boundary in boundaries {
      sceneLengths.append(boundary.timestamp - previousTimestamp)
      previousTimestamp = boundary.timestamp
    }

    // Add final scene length
    sceneLengths.append(videoAnalyzer.duration - previousTimestamp)

    let avgSceneLength = sceneLengths.reduce(0, +) / Double(sceneLengths.count)
    let minSceneLength = sceneLengths.min() ?? 0
    let maxSceneLength = sceneLengths.max() ?? 0

    print("  📊 Scene length statistics:")
    print("    Average: \(String(format: "%.1f", avgSceneLength))s")
    print("    Shortest: \(String(format: "%.1f", minSceneLength))s")
    print("    Longest: \(String(format: "%.1f", maxSceneLength))s")
  }
}
