import AVFoundation
import CoreImage
import Foundation
import Vision

/// Performs optical character recognition (OCR) on video frames.
class TextDetector: VideoReaderObserver {
  private let videoAnalyzer: VideoAnalyzer
  var videoInterval: Int { 30 } // Process every 30th frame (roughly 1 per second)

  var results: [(timestamp: Double, text: String, confidence: Float, boundingBox: CGRect)] = []
  
  private let textRecognitionRequest: VNRecognizeTextRequest

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
    
    // Initialize the request once
    self.textRecognitionRequest = VNRecognizeTextRequest()
    self.textRecognitionRequest.recognitionLevel = .accurate
    self.textRecognitionRequest.usesLanguageCorrection = true
    if #available(macOS 13.0, *) {
      self.textRecognitionRequest.revision = VNRecognizeTextRequestRevision3
    }
    self.textRecognitionRequest.recognitionLanguages = ["en-US"]
  }

  func processFrame(_ result: FrameResult) {
    let ciImage = CIImage(cvPixelBuffer: result.pixelBuffer)
    let timestamp = result.timestamp

    let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
    
    do {
      try handler.perform([textRecognitionRequest])
      
      if let observations = textRecognitionRequest.results {
        for observation in observations {
          if let topCandidate = observation.topCandidates(1).first, topCandidate.confidence > 0.6 {
            results.append((
              timestamp: timestamp,
              text: topCandidate.string,
              confidence: topCandidate.confidence,
              boundingBox: observation.boundingBox
            ))
          }
        }
      }
    } catch {
      logger.error("Text detection error at \(timestamp): \(error.localizedDescription)")
    }
  }
}
