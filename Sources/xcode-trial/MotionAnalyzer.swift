import AVFoundation
import CoreImage
import Foundation

class MotionAnalyzer {
  private let videoAnalyzer: VideoAnalyzer

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
  }

  func analyzeMotion() -> [(
    timestamp: Double, intensity: Double, direction: (x: Double, y: Double)?, type: String
  )] {
    print("⚡ Performing advanced motion analysis...")

    guard let videoTrack = videoAnalyzer.videoTrack else { return [] }

    let reader = try? AVAssetReader(asset: videoAnalyzer.asset)
    let outputSettings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
    reader?.add(trackOutput)

    guard reader?.startReading() == true else { return [] }

    var motionData:
      [(timestamp: Double, intensity: Double, direction: (x: Double, y: Double)?, type: String)] =
        []
    var frameCount = 0
    var previousFrameData: [UInt8]?

    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
      frameCount += 1

      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

      let frameData = videoAnalyzer.extractFrameData(from: pixelBuffer)
      let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

      if let previous = previousFrameData {
        // Calculate optical flow (simplified block matching)
        let motionVectors = calculateOpticalFlow(
          previous, frameData, width: CVPixelBufferGetWidth(pixelBuffer),
          height: CVPixelBufferGetHeight(pixelBuffer))

        // Calculate overall motion intensity
        let avgMotion =
          motionVectors.map { $0.magnitude }.reduce(0, +) / Double(motionVectors.count)

        // Determine motion type
        let motionType = classifyMotion(motionVectors, avgMotion)

        // Calculate average motion direction
        let avgDirection = calculateAverageDirection(motionVectors)

        motionData.append(
          (
            timestamp: timestamp,
            intensity: avgMotion,
            direction: avgDirection,
            type: motionType
          ))
      }

      previousFrameData = frameData

      if frameCount >= 100 { break }  // Demo limit
    }

    reader?.cancelReading()

    print("  ✅ Analyzed motion in \(motionData.count) frame pairs")

    // Analyze motion patterns
    analyzeMotionPatterns(motionData)

    return motionData
  }

  private func calculateOpticalFlow(_ frame1: [UInt8], _ frame2: [UInt8], width: Int, height: Int)
    -> [(x: Int, y: Int, magnitude: Double)]
  {
    // Simplified optical flow using block matching
    var motionVectors: [(x: Int, y: Int, magnitude: Double)] = []

    let blockSize = 32  // Increased block size
    let searchRange = 4  // Reduced search range

    // Sample blocks at larger intervals
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
    let positions = [
      (dx: 0, dy: 0),  // No motion
      (dx: -2, dy: 0),  // Left
      (dx: 2, dy: 0),  // Right
      (dx: 0, dy: -2),  // Up
      (dx: 0, dy: 2),  // Down
    ]

    var bestMatch = (dx: 0, dy: 0)
    var minDifference = Double.infinity

    for (dx, dy) in positions {
      let newX = x + dx
      let newY = y + dy

      // Check bounds
      if newX < 0 || newX + blockSize >= width || newY < 0 || newY + blockSize >= height {
        continue
      }

      // Calculate block difference
      let difference = calculateBlockDifference(
        frame1, frame2, x1: x, y1: y, x2: newX, y2: newY, blockSize: blockSize, width: width)

      if difference < minDifference {
        minDifference = difference
        bestMatch = (dx: dx, dy: dy)
      }
    }

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
    if avgMotion < 0.5 {
      return "static"
    } else if avgMotion < 2.0 {
      return "subtle"
    } else if avgMotion < 5.0 {
      // Check for directional motion
      let avgDirection = calculateAverageDirection(motionVectors)
      if let direction = avgDirection {
        let angle = atan2(direction.y, direction.x) * 180 / .pi
        if abs(angle) < 45 {
          return "right_pan"
        } else if abs(angle) > 135 {
          return "left_pan"
        } else if angle > 45 && angle < 135 {
          return "down_pan"
        } else {
          return "up_pan"
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
    let motionTypes = Dictionary(grouping: motionData) { $0.type }.mapValues { $0.count }

    print("  ⚡ Motion analysis results:")
    print("    Average motion intensity: \(String(format: "%.3f", avgMotion))")

    for (type, count) in motionTypes.sorted(by: { $0.value > $1.value }) {
      let percentage = Double(count) / Double(motionData.count) * 100
      print("    \(type): \(String(format: "%.1f", percentage))%")
    }

    // Detect motion bursts (sudden increases)
    var motionBursts = 0
    for i in 1..<motionData.count {
      if motionData[i].intensity > motionData[i - 1].intensity * 2.0 {
        motionBursts += 1
      }
    }

    if motionBursts > 0 {
      print("    Motion bursts detected: \(motionBursts)")
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
        print("    Dominant motion direction: \(String(format: "%.0f", angle))°")
      }
    }
  }
}
