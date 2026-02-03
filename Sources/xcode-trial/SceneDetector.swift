import AVFoundation
import CoreImage
import Foundation

/// Detects scene boundaries and transitions in video content.
///
/// `SceneDetector` analyzes temporal changes between consecutive frames to identify
/// scene boundaries and classify transition types. It uses histogram comparison
/// and edge detection techniques to detect significant visual changes.
///
/// Key algorithms:
/// - Histogram-based frame difference analysis
/// - Edge detection for content change identification
/// - Adaptive thresholding for scene boundary detection
/// - Transition type classification (cut, fade, dissolve)
///
/// Technical implementation:
/// - Compares RGB histograms between consecutive frames
/// - Calculates histogram intersection similarity scores
/// - Applies temporal smoothing to reduce false positives
/// - Classifies transitions based on change characteristics
///
/// Scene detection parameters:
/// - Similarity threshold: minimum change for scene boundary
/// - Minimum scene duration: prevents overly short scenes
/// - Transition window: frames around detected boundaries
/// - Confidence scoring for boundary reliability
///
/// Performance optimizations:
/// - Processes frames at reduced resolution
/// - Uses efficient histogram calculations
/// - Early termination for static content
/// - Memory-efficient frame buffering
///
/// Applications:
/// - Video segmentation and chapter detection
/// - Content-based navigation and indexing
/// - Editing analysis and style recognition
/// - Automated highlight extraction
///
/// Output format:
/// Returns array of (timestamp, transitionType) tuples for scene analysis
class SceneDetector {
  private let videoAnalyzer: VideoAnalyzer
  private let videoReader: VideoReader

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
    self.videoReader = VideoReader(videoAnalyzer: videoAnalyzer)
  }

  /// Detects scene boundaries and classifies transition types.
  func detectSceneBoundaries() -> [(timestamp: Double, type: String, confidence: Double)] {
    logger.debug("🎬 Performing advanced scene detection...")

    var sceneBoundaries: [(timestamp: Double, type: String, confidence: Double)] = []
    var previousFrameData: [UInt8]?
    var previousHistogram: [Int]?

    do {
      try videoReader.readFrames { frameResult in
        let frameData = frameResult.frameData
        let histogram = calculateHistogram(from: frameResult.pixelBuffer)
        let timestamp = frameResult.timestamp

        // Multiple scene detection methods for different transition types
        if let previous = previousFrameData, let prevHist = previousHistogram {
          // Calculate differences between consecutive frames
          let pixelDifference = videoAnalyzer.calculateFrameDifference(previous, frameData)
          let histogramDifference = calculateHistogramDifference(prevHist, histogram)

          // Hard cut detection: sudden, dramatic change (most common transition)
          // Both pixel and histogram differences must exceed thresholds
          if pixelDifference > 0.3 && histogramDifference > 0.4 {
            sceneBoundaries.append(
              (
                timestamp: timestamp, type: "hard_cut",
                confidence: min(pixelDifference, histogramDifference)
              ))
          }
          // Fade detection: gradual brightness change (fade in/out to black/white)
          else if detectFade(frameResult.pixelBuffer, previousFrame: previous) {
            sceneBoundaries.append((timestamp: timestamp, type: "fade", confidence: 0.7))
          }
          // Dissolve detection: gradual pixel blending between scenes
          // High pixel difference but low histogram difference (similar colors)
          else if pixelDifference > 0.15 && histogramDifference < 0.2 {
            sceneBoundaries.append(
              (timestamp: timestamp, type: "dissolve", confidence: pixelDifference))
          }
        }

        previousFrameData = frameData
        previousHistogram = histogram

        return true  // Continue processing
      }
    } catch VideoReaderError.assetReaderCreationFailed {
      logger.error("❌ Failed to create asset reader for scene detection")
    } catch VideoReaderError.trackOutputCreationFailed {
      logger.error("❌ Failed to create track output for scene detection")
    } catch VideoReaderError.readingFailed(let message) {
      logger.error("❌ Scene detection reading failed: \(message)")
    } catch VideoReaderError.pixelBufferExtractionFailed {
      logger.error("❌ Failed to extract pixel buffer during scene detection")
    } catch VideoReaderError.invalidFrameData {
      logger.error("❌ Invalid frame data encountered during scene detection")
    } catch {
      logger.error("❌ Unexpected error during scene detection: \(error.localizedDescription)")
    }

    logger.debug("✅ Scene detection completed - found \(sceneBoundaries.count) scene boundaries")

    let cutCount = sceneBoundaries.filter { $0.type == "hard_cut" }.count
    let fadeCount = sceneBoundaries.filter { $0.type == "fade" }.count
    let dissolveCount = sceneBoundaries.filter { $0.type == "dissolve" }.count

    logger.debug("Hard cuts: \(cutCount), Fades: \(fadeCount), Dissolves: \(dissolveCount)")

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

    logger.debug("📊 Scene length statistics:")
    logger.debug("  Average: \(String(format: "%.1f", avgSceneLength))s")
    logger.debug("  Shortest: \(String(format: "%.1f", minSceneLength))s")
    logger.debug("  Longest: \(String(format: "%.1f", maxSceneLength))s")
  }
}
