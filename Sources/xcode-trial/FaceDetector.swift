import AVFoundation
import CoreImage
import Foundation
import Vision

class FaceDetector {
  private let videoAnalyzer: VideoAnalyzer

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
  }

  func analyzeFaces() -> [(timestamp: Double, count: Int, landmarks: VNFaceLandmarks2D?)] {
    print("🎭 Performing detailed face analysis...")

    guard let videoTrack = videoAnalyzer.videoTrack else { return [] }

    let reader = try? AVAssetReader(asset: videoAnalyzer.asset)
    let outputSettings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
    reader?.add(trackOutput)

    guard reader?.startReading() == true else { return [] }

    var results: [(timestamp: Double, count: Int, landmarks: VNFaceLandmarks2D?)] = []
    var frameCount = 0

    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
      frameCount += 1

      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

      let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
      let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

      // Face detection with landmarks
      let faceDetectionRequest = VNDetectFaceLandmarksRequest { request, error in
        guard let observations = request.results as? [VNFaceObservation] else { return }

        if !observations.isEmpty {
          results.append(
            (
              timestamp: timestamp,
              count: observations.count,
              landmarks: observations.first?.landmarks
            ))
        }
      }

      faceDetectionRequest.revision = VNDetectFaceLandmarksRequestRevision3

      let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
      try? handler.perform([faceDetectionRequest])

      if frameCount >= 500 { break }  // Demo limit
    }

    reader?.cancelReading()

    print("  ✅ Detected faces in \(results.count) frames")
    let totalFaces = results.reduce(0) { $0 + $1.count }
    print("  👥 Total faces: \(totalFaces)")

    // Analyze face presence patterns
    analyzeFacePatterns(results)

    return results
  }

  private func analyzeFacePatterns(
    _ faceData: [(timestamp: Double, count: Int, landmarks: VNFaceLandmarks2D?)]
  ) {
    if faceData.isEmpty { return }

    let facePresentFrames = faceData.count
    let totalFrames = 500  // Based on our demo limit
    let facePresenceRate = Double(facePresentFrames) / Double(totalFrames) * 100

    print("  📊 Face presence: \(String(format: "%.1f", facePresenceRate))% of frames")

    // Calculate average faces per frame when present
    let avgFacesWhenPresent = Double(faceData.reduce(0) { $0 + $1.count }) / Double(faceData.count)
    print("  👨‍👩‍👧‍👦 Average faces when present: \(String(format: "%.1f", avgFacesWhenPresent))")

    // Detect face landmarks if available
    let framesWithLandmarks = faceData.filter { $0.landmarks != nil }.count
    if framesWithLandmarks > 0 {
      print("  🎯 Facial landmarks detected in \(framesWithLandmarks) frames")
    }
  }

  func detectSpeakerChanges(
    _ faceData: [(timestamp: Double, count: Int, landmarks: VNFaceLandmarks2D?)]
  ) -> [Double] {
    // Simple speaker change detection based on face count changes
    var speakerChanges: [Double] = []
    var previousFaceCount = 0

    for data in faceData {
      if abs(data.count - previousFaceCount) >= 1 && previousFaceCount > 0 {
        speakerChanges.append(data.timestamp)
      }
      previousFaceCount = data.count
    }

    return speakerChanges
  }
}
