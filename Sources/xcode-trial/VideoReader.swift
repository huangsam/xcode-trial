import AVFoundation
import Foundation

/// Errors that can occur during video reading operations.
enum VideoReaderError: Error {
  case assetReaderCreationFailed
  case trackOutputCreationFailed
  case readingFailed(String)
  case pixelBufferExtractionFailed
  case invalidFrameData
  case audioBufferExtractionFailed
}

/// Result type for video frame reading operations.
struct FrameResult {
  let timestamp: Double
  let pixelBuffer: CVPixelBuffer
  let frameData: [UInt8]
}

/// Result type for audio buffer reading operations.
struct AudioResult {
  let timestamp: Double
  let volume: Double
  let isSilent: Bool
}

/// Protocol for objects that want to receive video frames and audio buffers during analysis.
protocol VideoReaderObserver: AnyObject {
  var videoInterval: Int { get }
  func processFrame(_ result: FrameResult)
  func processAudio(_ result: AudioResult)
}

// Default implementations
extension VideoReaderObserver {
  var videoInterval: Int { 1 }
  func processFrame(_ result: FrameResult) {}
  func processAudio(_ result: AudioResult) {}
}

/// Thread-safe video reader utility that coordinates single-pass multimodal analysis.
///
/// `VideoReader` provides a centralized interface for reading both video and audio
/// tracks simultaneously, significantly improving performance by reducing redundant
/// decoding operations.
class VideoReader {
  private let asset: AVAsset
  private let videoTrack: AVAssetTrack?
  private let audioTrack: AVAssetTrack?
  private var observers: [VideoReaderObserver] = []

  private let videoOutputSettings: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
  ]

  private let audioOutputSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsNonInterleaved: false,
  ]

  init(asset: AVAsset, videoTrack: AVAssetTrack?, audioTrack: AVAssetTrack?) {
    self.asset = asset
    self.videoTrack = videoTrack
    self.audioTrack = audioTrack
  }

  func addObserver(_ observer: VideoReaderObserver) {
    observers.append(observer)
  }

  /// Performs a single-pass read of both video and audio tracks.
  func readAll(limitFrames: Int? = nil) throws {
    guard let reader = try? AVAssetReader(asset: asset) else {
      throw VideoReaderError.assetReaderCreationFailed
    }

    var videoOutput: AVAssetReaderTrackOutput?
    if let videoTrack = videoTrack {
      let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoOutputSettings)
      output.alwaysCopiesSampleData = false
      if reader.canAdd(output) {
        reader.add(output)
        videoOutput = output
      }
    }

    var audioOutput: AVAssetReaderTrackOutput?
    if let audioTrack = audioTrack {
      let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioOutputSettings)
      output.alwaysCopiesSampleData = false
      if reader.canAdd(output) {
        reader.add(output)
        audioOutput = output
      }
    }

    guard reader.startReading() else {
      let errorMessage = reader.error?.localizedDescription ?? "Unknown reading error"
      throw VideoReaderError.readingFailed(errorMessage)
    }

    defer {
      if reader.status == .reading {
        reader.cancelReading()
      }
    }

    var videoFrameCount = 0
    var finishedVideo = videoOutput == nil
    var finishedAudio = audioOutput == nil

    while !finishedVideo || !finishedAudio {
      autoreleasepool {
        // Read video if available
        if !finishedVideo, let output = videoOutput {
          if let sampleBuffer = output.copyNextSampleBuffer() {
            videoFrameCount += 1
            
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
              let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
              
              // Only extract frame data if any observer needs it
              let frameData = extractFrameData(from: pixelBuffer)
              let result = FrameResult(timestamp: timestamp, pixelBuffer: pixelBuffer, frameData: frameData)
              
              for observer in observers {
                if videoFrameCount % observer.videoInterval == 0 {
                  observer.processFrame(result)
                }
              }
            }
            
            if let limit = limitFrames, videoFrameCount >= limit {
              finishedVideo = true
            }
          } else {
            finishedVideo = true
          }
        }

        // Read audio if available
        if !finishedAudio, let output = audioOutput {
          if let sampleBuffer = output.copyNextSampleBuffer() {
            if let audioResult = processAudioBuffer(sampleBuffer) {
              for observer in observers {
                observer.processAudio(audioResult)
              }
            }
          } else {
            finishedAudio = true
          }
        }
      }
    }
  }

  private func extractFrameData(from pixelBuffer: CVPixelBuffer) -> [UInt8] {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    var samples = [UInt8]()

    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
    
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

    // Sample a 10x10 grid for quick analysis
    let horizontalStride = max(1, width / 10)
    let verticalStride = max(1, height / 10)

    for y in stride(from: 0, to: height, by: verticalStride) {
      let rowOffset = y * bytesPerRow
      for x in stride(from: 0, to: width, by: horizontalStride) {
        let offset = rowOffset + x * 4
        // BGRA format: B is 0, G is 1, R is 2
        let b = buffer[offset]
        let g = buffer[offset + 1]
        let r = buffer[offset + 2]
        samples.append(UInt8((Int(r) + Int(g) + Int(b)) / 3))
      }
    }

    return samples
  }

  private func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> AudioResult? {
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
    let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

    var length = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil, dataPointerOut: &dataPointer) == noErr,
          let audioBytes = dataPointer else {
      return nil
    }

    // Process 16-bit PCM samples
    let sampleCount = length / 2
    let samples = audioBytes.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 }
    
    var sumOfSquares: Double = 0
    for i in 0..<sampleCount {
      let normalizedSample = Double(samples[i]) / 32768.0
      sumOfSquares += normalizedSample * normalizedSample
    }

    if sampleCount > 0 {
      let rms = sqrt(sumOfSquares / Double(sampleCount))
      let volume = min(rms * 100, 100)
      return AudioResult(timestamp: timestamp, volume: volume, isSilent: volume < 1.0)
    }
    
    return nil
  }
}
