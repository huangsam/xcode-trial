import AVFoundation
import CoreImage
import Foundation

/// Errors that can occur during video reading operations.
enum VideoReaderError: Error {
  case assetReaderCreationFailed
  case trackOutputCreationFailed
  case readingFailed(String)
  case pixelBufferExtractionFailed
  case invalidFrameData
}

/// Result type for video frame reading operations.
struct FrameResult {
  let timestamp: Double
  let pixelBuffer: CVPixelBuffer
  let frameData: [UInt8]
}

/// Thread-safe video reader utility that eliminates code duplication across analyzers.
///
/// `VideoReader` provides a centralized, type-safe interface for reading video frames
/// with proper error handling and resource management. It abstracts away the common
/// AVFoundation setup and reading patterns used by all analyzer classes.
///
/// Key features:
/// - Type-safe error handling with custom error types
/// - Automatic resource cleanup
/// - Configurable frame processing
/// - Memory-efficient frame data extraction
///
/// Usage pattern:
/// ```swift
/// let reader = VideoReader(videoAnalyzer: analyzer)
/// try reader.readFrames { frameResult in
///     // Process each frame
///     return true // continue processing
/// }
/// ```
class VideoReader {
  private let videoAnalyzer: VideoAnalyzer
  private let outputSettings: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
  ]

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
  }

  /// Reads video frames sequentially, calling the provided closure for each frame.
  ///
  /// - Parameter processFrame: Closure called for each frame with frame data.
  ///   Return true to continue processing, false to stop.
  /// - Throws: VideoReaderError if reading fails
  func readFrames(processFrame: (FrameResult) throws -> Bool) throws {
    guard let videoTrack = videoAnalyzer.videoTrack else {
      throw VideoReaderError.trackOutputCreationFailed
    }

    guard let reader = try? AVAssetReader(asset: videoAnalyzer.asset) else {
      throw VideoReaderError.assetReaderCreationFailed
    }

    let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
    reader.add(trackOutput)

    guard reader.startReading() else {
      let errorMessage = reader.error?.localizedDescription ?? "Unknown reading error"
      throw VideoReaderError.readingFailed(errorMessage)
    }

    defer {
      reader.cancelReading()  // Ensure cleanup
    }

    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        throw VideoReaderError.pixelBufferExtractionFailed
      }

      let frameData = videoAnalyzer.extractFrameData(from: pixelBuffer)
      guard !frameData.isEmpty else {
        throw VideoReaderError.invalidFrameData
      }

      let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

      let frameResult = FrameResult(
        timestamp: timestamp,
        pixelBuffer: pixelBuffer,
        frameData: frameData
      )

      let shouldContinue = try processFrame(frameResult)
      if !shouldContinue {
        break
      }
    }
  }

  /// Reads frames at a specified interval for performance optimization.
  ///
  /// - Parameters:
  ///   - interval: Process every Nth frame (1 = every frame, 2 = every other frame, etc.)
  ///   - processFrame: Closure called for each selected frame
  /// - Throws: VideoReaderError if reading fails
  func readFrames(interval: Int, processFrame: (FrameResult) throws -> Bool) throws {
    var frameCount = 0
    try readFrames { frameResult in
      frameCount += 1
      if frameCount % interval == 0 {
        return try processFrame(frameResult)
      }
      return true
    }
  }
}
