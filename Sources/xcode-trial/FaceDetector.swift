import AVFoundation
import CoreImage
import Foundation
import Vision

/// Detects and analyzes faces in video frames using Apple's Vision framework.
class FaceDetector: VideoReaderObserver {
  private let videoAnalyzer: VideoAnalyzer
  var videoInterval: Int { 10 } // Process every 10th frame

  var results: [(timestamp: Double, count: Int, landmarks: VNFaceLandmarks2D?)] = []
  
  // Reuse the request object for better performance
  private let faceDetectionRequest = VNDetectFaceLandmarksRequest()

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
  }

  func processFrame(_ result: FrameResult) {
    let ciImage = CIImage(cvPixelBuffer: result.pixelBuffer)
    let timestamp = result.timestamp

    let requestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])

    do {
      try requestHandler.perform([faceDetectionRequest])

      if let observations = faceDetectionRequest.results, !observations.isEmpty {
        let firstFace = observations[0]
        results.append((
          timestamp: timestamp,
          count: observations.count,
          landmarks: firstFace.landmarks
        ))
      }
    } catch {
      logger.error("Face detection error at \(timestamp): \(error.localizedDescription)")
    }
  }

  /// Detects potential speaker changes based on face count variations.
  func detectSpeakerChanges() -> [Double] {
    var speakerChanges: [Double] = []
    var previousFaceCount = 0

    for data in results {
      if abs(data.count - previousFaceCount) >= 1 && previousFaceCount > 0 {
        speakerChanges.append(data.timestamp)
      }
      previousFaceCount = data.count
    }

    return speakerChanges
  }
}
