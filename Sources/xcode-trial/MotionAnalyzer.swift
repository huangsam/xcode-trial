import AVFoundation
import Foundation

/// Analyzes motion and optical flow between consecutive video frames.
class MotionAnalyzer: VideoReaderObserver {
  private let videoAnalyzer: VideoAnalyzer
  var videoInterval: Int { 1 } // Process every frame for smooth motion analysis

  var motionData: [(timestamp: Double, intensity: Double, direction: (x: Double, y: Double)?, type: String)] = []
  private var previousFrameData: [UInt8]?

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
  }

  func processFrame(_ result: FrameResult) {
    let currentFrameData = result.frameData
    let timestamp = result.timestamp

    if let previous = previousFrameData {
      let intensity = videoAnalyzer.calculateFrameDifference(previous, currentFrameData)
      
      // Classify motion intensity level
      let motionType = classifyMotion(intensity)

      motionData.append((
        timestamp: timestamp,
        intensity: intensity,
        direction: nil,
        type: motionType
      ))
    }

    previousFrameData = currentFrameData
  }

  private func classifyMotion(_ intensity: Double) -> String {
    if intensity < 0.05 { return "static" }
    if intensity < 0.2 { return "subtle" }
    if intensity < 0.5 { return "motion" }
    return "action"
  }
}
