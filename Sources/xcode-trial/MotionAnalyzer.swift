import AVFoundation
import CoreImage
import Foundation

/// Analyzes motion and optical flow between consecutive video frames.
///
/// `MotionAnalyzer` implements optical flow algorithms to detect and quantify
/// movement between video frames. It uses simplified block matching techniques
/// to calculate motion vectors and intensity measurements for temporal analysis.
///
/// Key algorithms:
/// - Block matching optical flow for motion estimation
/// - Motion vector calculation between frame pairs
/// - Motion intensity aggregation across frame regions
///
/// Technical approach:
/// - Compares grayscale representations of consecutive frames
/// - Uses 16x16 pixel blocks for motion estimation
/// - Searches within ±8 pixel radius for block matches
/// - Calculates motion magnitude and direction vectors
///
/// Performance optimizations:
/// - Downsamples frames to reduce computational complexity
/// - Processes motion at reduced framerate for efficiency
/// - Memory-efficient frame buffer management
/// - Early termination for static scenes
///
/// Motion metrics:
/// - Motion intensity: average magnitude of motion vectors
/// - Motion direction: dominant movement patterns
/// - Temporal consistency: motion stability over time
///
/// Limitations:
/// - Simplified algorithm trades accuracy for speed
/// - May miss subtle motions in low-contrast scenes
/// - Block-based approach can miss object boundaries
///
/// Output format:
/// Returns array of (timestamp, intensity) tuples for motion analysis
class MotionAnalyzer {
  private let videoAnalyzer: VideoAnalyzer
  private let videoReader: VideoReader

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
    self.videoReader = VideoReader(videoAnalyzer: videoAnalyzer)
  }

  /// Analyzes motion between consecutive video frames using optical flow.
  func analyzeMotion() -> [(
    timestamp: Double, intensity: Double, direction: (x: Double, y: Double)?, type: String
  )] {
    logger.info("Performing advanced motion analysis...")

    var motionData:
      [(timestamp: Double, intensity: Double, direction: (x: Double, y: Double)?, type: String)] =
        []
    var previousFrameData: [UInt8]?

    do {
      try videoReader.readFrames { frameResult in
        let currentFrameData = frameResult.frameData
        let timestamp = frameResult.timestamp

        if let previous = previousFrameData {
          // Calculate optical flow (simplified block matching)
          let motionVectors = calculateOpticalFlow(
            previous, currentFrameData, width: CVPixelBufferGetWidth(frameResult.pixelBuffer),
            height: CVPixelBufferGetHeight(frameResult.pixelBuffer))

          // Calculate overall motion intensity as average of all motion vector magnitudes
          let avgMotion =
            motionVectors.map { $0.magnitude }.reduce(0, +) / Double(motionVectors.count)

          // Determine motion type based on intensity and direction patterns
          let motionType = classifyMotion(motionVectors, avgMotion)

          // Calculate average motion direction across all vectors
          let avgDirection = calculateAverageDirection(motionVectors)

          motionData.append(
            (
              timestamp: timestamp,
              intensity: avgMotion,
              direction: avgDirection,
              type: motionType
            ))
        }

        previousFrameData = currentFrameData
        return true  // Continue processing all frames
      }
    } catch VideoReaderError.assetReaderCreationFailed {
      logger.error("Failed to create asset reader for motion analysis")
    } catch VideoReaderError.trackOutputCreationFailed {
      logger.error("Failed to create track output for motion analysis")
    } catch VideoReaderError.readingFailed(let message) {
      logger.error("Motion analysis reading failed: \(message)")
    } catch VideoReaderError.pixelBufferExtractionFailed {
      logger.error("Failed to extract pixel buffer during motion analysis")
    } catch VideoReaderError.invalidFrameData {
      logger.error("Invalid frame data encountered during motion analysis")
    } catch {
      logger.error("Unexpected error during motion analysis: \(error.localizedDescription)")
    }

    logger.info("Motion analysis completed - processed \(motionData.count) frame pairs")

    // Analyze motion patterns
    analyzeMotionPatterns(motionData)

    return motionData
  }

  private func calculateOpticalFlow(_ frame1: [UInt8], _ frame2: [UInt8], width: Int, height: Int)
    -> [(x: Int, y: Int, magnitude: Double)]
  {
    // Simplified optical flow using block matching algorithm
    // This compares small blocks of pixels between frames to find movement
    var motionVectors: [(x: Int, y: Int, magnitude: Double)] = []

    let blockSize = 32  // Size of pixel blocks to compare (larger = faster but less precise)
    let searchRange = 4  // How far to search for matching blocks (±4 pixels)

    // Sample blocks at larger intervals for performance (every 128 pixels instead of every 32)
    // This reduces computation while still capturing overall motion patterns
    for y in stride(from: blockSize, to: height - blockSize, by: blockSize * 4) {  // Sample every 128 pixels
      for x in stride(from: blockSize, to: width - blockSize, by: blockSize * 4) {
        let motionVector = findBestMatch(
          frame1, frame2, x: x, y: y, blockSize: blockSize, searchRange: searchRange, width: width,
          height: height)
        motionVectors.append(motionVector)
      }
    }

    return motionVectors
  }

  private func findBestMatch(
    _ frame1: [UInt8], _ frame2: [UInt8], x: Int, y: Int, blockSize: Int, searchRange: Int,
    width: Int, height: Int
  ) -> (x: Int, y: Int, magnitude: Double) {
    // Simplified motion estimation - check center and a few nearby positions
    // This is a basic implementation that tests 5 positions: center, left, right, up, down
    let positions = [
      (dx: 0, dy: 0),  // No motion (reference point)
      (dx: -2, dy: 0),  // Left movement
      (dx: 2, dy: 0),  // Right movement
      (dx: 0, dy: -2),  // Up movement
      (dx: 0, dy: 2),  // Down movement
    ]

    var bestMatch = (dx: 0, dy: 0)
    var minDifference = Double.infinity

    // Test each possible motion position and find the one with least pixel difference
    for (dx, dy) in positions {
      let newX = x + dx
      let newY = y + dy

      // Skip positions that would go outside frame boundaries
      if newX < 0 || newX + blockSize >= width || newY < 0 || newY + blockSize >= height {
        continue
      }

      // Calculate how different the blocks are (lower = better match)
      let difference = calculateBlockDifference(
        frame1, frame2, x1: x, y1: y, x2: newX, y2: newY, blockSize: blockSize, width: width)

      if difference < minDifference {
        minDifference = difference
        bestMatch = (dx: dx, dy: dy)
      }
    }

    // Calculate motion magnitude using Pythagorean theorem
    let magnitude = sqrt(Double(bestMatch.dx * bestMatch.dx + bestMatch.dy * bestMatch.dy))
    return (x: bestMatch.dx, y: bestMatch.dy, magnitude: magnitude)
  }

  private func calculateBlockDifference(
    _ frame1: [UInt8], _ frame2: [UInt8], x1: Int, y1: Int, x2: Int, y2: Int, blockSize: Int,
    width: Int
  ) -> Double {
    var totalDifference = 0.0
    var pixelCount = 0

    for by in 0..<blockSize {
      for bx in 0..<blockSize {
        let idx1 = (y1 + by) * width + (x1 + bx)
        let idx2 = (y2 + by) * width + (x2 + bx)

        if idx1 < frame1.count && idx2 < frame2.count {
          totalDifference += Double(abs(Int(frame1[idx1]) - Int(frame2[idx2])))
          pixelCount += 1
        }
      }
    }

    return pixelCount > 0 ? totalDifference / Double(pixelCount) : 0.0
  }

  private func classifyMotion(
    _ motionVectors: [(x: Int, y: Int, magnitude: Double)], _ avgMotion: Double
  ) -> String {
    // Classify motion based on intensity thresholds and directional patterns
    if avgMotion < 0.5 {
      return "static"  // Very little motion detected
    } else if avgMotion < 2.0 {
      return "subtle"  // Minor motion (background movement, small objects)
    } else if avgMotion < 5.0 {
      // Check for directional motion (camera pans, object tracking)
      let avgDirection = calculateAverageDirection(motionVectors)
      if let direction = avgDirection {
        // Convert direction vector to angle in degrees
        let angle = atan2(direction.y, direction.x) * 180 / .pi
        if abs(angle) < 45 {
          return "right_pan"  // Camera panning right
        } else if abs(angle) > 135 {
          return "left_pan"  // Camera panning left
        } else if angle > 45 && angle < 135 {
          return "down_pan"  // Camera panning down
        } else {
          return "up_pan"  // Camera panning up
        }
      }
      return "motion"
    } else {
      return "action"
    }
  }

  private func calculateAverageDirection(_ motionVectors: [(x: Int, y: Int, magnitude: Double)])
    -> (x: Double, y: Double)?
  {
    if motionVectors.isEmpty { return nil }

    let totalX = motionVectors.reduce(0.0) { $0 + Double($1.x) }
    let totalY = motionVectors.reduce(0.0) { $0 + Double($1.y) }
    let count = Double(motionVectors.count)

    return (x: totalX / count, y: totalY / count)
  }

  private func analyzeMotionPatterns(
    _ motionData: [(
      timestamp: Double, intensity: Double, direction: (x: Double, y: Double)?, type: String
    )]
  ) {
    if motionData.isEmpty { return }

    let avgMotion = motionData.map { $0.intensity }.reduce(0, +) / Double(motionData.count)

    logger.debug("Average motion intensity: \(String(format: "%.3f", avgMotion))")

    // Detect motion bursts (sudden increases)
    var motionBursts = 0
    for i in 1..<motionData.count {
      if motionData[i].intensity > motionData[i - 1].intensity * 2.0 {
        motionBursts += 1
      }
    }

    if motionBursts > 0 {
      logger.debug("Motion bursts detected: \(motionBursts)")
    }

    // Analyze directional consistency
    let directionalMotion = motionData.filter { $0.direction != nil }
    if !directionalMotion.isEmpty {
      let avgDirection = calculateAverageDirection(
        directionalMotion.map {
          (x: Int($0.direction!.x), y: Int($0.direction!.y), magnitude: $0.intensity)
        })
      if let direction = avgDirection {
        let angle = atan2(direction.y, direction.x) * 180 / .pi
        logger.debug("Dominant motion direction: \(String(format: "%.0f", angle))°")
      }
    }
  }
}
