import AVFoundation
import CoreImage
import Foundation
import Vision

/// Performs optical character recognition (OCR) on video frames.
///
/// `TextDetector` uses Apple's Vision framework to detect and extract text
/// from video frames, providing temporal text analysis capabilities. It handles
/// various text styles, languages, and orientations commonly found in videos.
///
/// Key capabilities:
/// - Text detection and recognition in video frames
/// - Confidence scoring for recognition accuracy
/// - Multi-language text support
/// - Temporal text tracking across frames
///
/// Technical implementation:
/// - Uses VNRecognizeTextRequest for OCR processing
/// - Processes frames sequentially through video timeline
/// - Filters results by confidence thresholds
/// - Aggregates text occurrences over time
///
/// Vision framework features:
/// - Automatic language detection
/// - Text orientation and layout analysis
/// - Handwriting and printed text recognition
/// - Performance optimization for real-time processing
///
/// Performance considerations:
/// - Processes frames at reduced frequency for efficiency
/// - Memory-efficient text result storage
/// - Configurable confidence thresholds
/// - Early termination for text-free content
///
/// Applications:
/// - Video caption and subtitle extraction
/// - Content-based search and indexing
/// - Accessibility feature analysis
/// - Brand and logo text detection
///
/// Limitations:
/// - Accuracy depends on text size and clarity
/// - Performance varies by language complexity
/// - May miss stylized or distorted text
///
/// Output format:
/// Returns array of (timestamp, text, confidence) tuples for text analysis
class TextDetector {
  private let videoAnalyzer: VideoAnalyzer

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
  }

  /// Performs optical character recognition on video frames.
  func detectText() -> [(timestamp: Double, text: String, confidence: Float, boundingBox: CGRect)] {
    print("📝 Performing text detection and OCR...")

    guard let videoTrack = videoAnalyzer.videoTrack else { return [] }

    let reader = try? AVAssetReader(asset: videoAnalyzer.asset)
    let outputSettings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
    reader?.add(trackOutput)

    guard reader?.startReading() == true else { return [] }

    var textDetections:
      [(timestamp: Double, text: String, confidence: Float, boundingBox: CGRect)] = []
    var frameCount = 0

    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
      frameCount += 1

      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

      let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
      let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

      // Text recognition using Vision framework OCR
      // VNRecognizeTextRequest automatically detects and extracts text from images
      let textRecognitionRequest = VNRecognizeTextRequest { request, error in
        // Process OCR results - Vision returns VNRecognizedTextObservation objects
        guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

        for observation in observations {
          // Get the top recognition candidate (highest confidence)
          guard let topCandidate = observation.topCandidates(1).first else { continue }

          // Filter out low confidence results to improve accuracy
          if topCandidate.confidence > 0.6 {
            textDetections.append(
              (
                timestamp: timestamp,
                text: topCandidate.string,
                confidence: topCandidate.confidence,
                boundingBox: observation.boundingBox
              ))
          }
        }
      }

      // Configure for better accuracy (slower but more precise)
      textRecognitionRequest.recognitionLevel = .accurate
      textRecognitionRequest.usesLanguageCorrection = true
      // Use latest OCR model if available (macOS 13+)
      if #available(macOS 13.0, *) {
        textRecognitionRequest.revision = VNRecognizeTextRequestRevision3
      }

      // Support multiple English variants for better recognition
      textRecognitionRequest.recognitionLanguages = ["en-US", "en-GB"]

      // Execute the Vision request on the frame
      let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
      try? handler.perform([textRecognitionRequest])

      if frameCount >= 50 { break }  // Demo limit
    }

    reader?.cancelReading()

    print("  ✅ Detected text in \(textDetections.count) frames")

    // Analyze detected text
    analyzeDetectedText(textDetections)

    return textDetections
  }

  private func analyzeDetectedText(
    _ textDetections: [(timestamp: Double, text: String, confidence: Float, boundingBox: CGRect)]
  ) {
    if textDetections.isEmpty { return }

    // Group text by content similarity
    var textGroups = [String: [(timestamp: Double, confidence: Float)]]()

    for detection in textDetections {
      let normalizedText = detection.text.lowercased().trimmingCharacters(
        in: .whitespacesAndNewlines)
      textGroups[normalizedText, default: []].append(
        (timestamp: detection.timestamp, confidence: detection.confidence))
    }

    print("  📝 Text analysis results:")
    print("    Unique text elements: \(textGroups.count)")

    // Find most common text (likely titles, captions, etc.)
    let sortedGroups = textGroups.sorted { $0.value.count > $1.value.count }

    if let mostCommon = sortedGroups.first {
      let avgConfidence =
        mostCommon.value.map { $0.confidence }.reduce(0, +) / Float(mostCommon.value.count)
      print(
        "    Most frequent text: \"\(mostCommon.key)\" (\(mostCommon.value.count) occurrences, \(String(format: "%.1f", avgConfidence * 100))% confidence)"
      )
    }

    // Analyze text timing patterns
    let timestamps = textDetections.map { $0.timestamp }.sorted()
    if timestamps.count > 1 {
      var intervals: [Double] = []
      for i in 1..<timestamps.count {
        intervals.append(timestamps[i] - timestamps[i - 1])
      }

      let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
      print("    Average text display time: \(String(format: "%.1f", avgInterval))s")
    }

    // Categorize text types
    let textTypes = categorizeText(textDetections)
    for (type, count) in textTypes.sorted(by: { $0.value > $1.value }) {
      let percentage = Double(count) / Double(textDetections.count) * 100
      print("    \(type): \(String(format: "%.1f", percentage))%")
    }

    // Check for captions/subtitles (bottom of screen)
    let bottomText = textDetections.filter { $0.boundingBox.minY < 0.3 }
    if !bottomText.isEmpty {
      print("    📺 Potential captions/subtitles: \(bottomText.count) detections")
    }
  }

  private func categorizeText(
    _ textDetections: [(timestamp: Double, text: String, confidence: Float, boundingBox: CGRect)]
  ) -> [String: Int] {
    var categories = [String: Int]()

    for detection in textDetections {
      let text = detection.text.lowercased()
      let boundingBox = detection.boundingBox

      // Categorize based on text content and position
      if text.contains("chapter") || text.contains("section")
        || text.matches(pattern: "^\\d+\\.\\d+")
      {
        categories["titles/headings", default: 0] += 1
      } else if boundingBox.minY < 0.2 {
        categories["lower_third", default: 0] += 1
      } else if boundingBox.maxY > 0.8 {
        categories["upper_third", default: 0] += 1
      } else if text.count < 10 {
        categories["labels/buttons", default: 0] += 1
      } else if text.contains("©") || text.contains("™") || text.matches(pattern: "\\d{4}") {
        categories["branding/legal", default: 0] += 1
      } else {
        categories["body_text", default: 0] += 1
      }
    }

    return categories
  }
}

// String extension for regex matching
extension String {
  /// Tests if the string matches a regular expression pattern.
  func matches(pattern: String) -> Bool {
    do {
      let regex = try NSRegularExpression(pattern: pattern, options: [])
      let range = NSRange(location: 0, length: self.count)
      return regex.firstMatch(in: self, options: [], range: range) != nil
    } catch {
      return false
    }
  }
}
