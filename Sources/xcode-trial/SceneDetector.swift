import AVFoundation
import Foundation

/// Detects scene boundaries and transitions in video content.
class SceneDetector: VideoReaderObserver {
  private let videoAnalyzer: VideoAnalyzer
  var videoInterval: Int { 5 } // Process every 5 frames for scene detection

  var sceneBoundaries: [(timestamp: Double, type: String, confidence: Double)] = []
  private var previousFrameData: [UInt8]?

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
  }

  func processFrame(_ result: FrameResult) {
    let currentData = result.frameData
    let timestamp = result.timestamp

    if let previous = previousFrameData {
      let pixelDifference = videoAnalyzer.calculateFrameDifference(previous, currentData)
      
      // If the difference between current and previous frame is high (40%), it's a scene change
      if pixelDifference > 0.4 {
        sceneBoundaries.append((timestamp: timestamp, type: "hard_cut", confidence: pixelDifference))
      }
    }

    previousFrameData = currentData
  }
}
