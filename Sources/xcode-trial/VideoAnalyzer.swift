import AVFoundation
import CoreImage
import Foundation
import Vision

/// The main video analysis orchestrator that coordinates multimodal analysis of video content.
///
/// `VideoAnalyzer` serves as the central hub for comprehensive video analysis, managing
/// specialized analyzers for different aspects of video content including faces, scenes,
/// colors, motion, audio, and text. It handles video asset loading, metadata extraction,
/// and coordinates the execution of all analysis types.
///
/// Key responsibilities:
/// - Video asset management and metadata loading
/// - Coordination of specialized analysis modules
/// - Result aggregation and statistics collection
/// - Performance optimization through lazy initialization
///
/// Design decisions:
/// - Uses lazy initialization for analyzers to avoid self-reference issues
/// - Maintains backward compatibility with legacy result arrays
/// - Delegates complex analysis to specialized single-responsibility classes
///
/// Dependencies:
/// - AVFoundation for video asset handling
/// - Vision framework for computer vision tasks
/// - CoreImage for image processing operations
///
/// Example usage:
/// ```swift
/// let analyzer = VideoAnalyzer(videoPath: "/path/to/video.mp4")
/// analyzer.analyzeBasicInfo()
/// analyzer.analyzeFaces()
/// ```
class VideoAnalyzer {
  let videoPath: String
  let asset: AVAsset
  var videoTrack: AVAssetTrack?
  var duration: Double = 0
  var frameRate: Float = 0
  var dimensions: CGSize = .zero
  var totalFrames: Int = 0

  // Specialized analyzers (lazy to avoid self before init)
  lazy var faceDetector: FaceDetector = FaceDetector(videoAnalyzer: self)
  lazy var sceneDetector: SceneDetector = SceneDetector(videoAnalyzer: self)
  lazy var colorAnalyzer: ColorAnalyzer = ColorAnalyzer(videoAnalyzer: self)
  lazy var motionAnalyzer: MotionAnalyzer = MotionAnalyzer(videoAnalyzer: self)
  lazy var textDetector: TextDetector = TextDetector(videoAnalyzer: self)
  lazy var audioAnalyzer: AudioAnalyzer = AudioAnalyzer(videoAnalyzer: self)
  lazy var statisticsCollector: StatisticsCollector = StatisticsCollector()

  // Public access to statistics collector
  var stats: StatisticsCollector { statisticsCollector }

  // Analysis results (kept for backward compatibility)
  var backgroundChanges: [(timestamp: Double, frame: Int)] = []
  var facesDetected: [(timestamp: Double, count: Int, landmarks: VNFaceLandmarks2D?)] = []
  var sceneBoundaries: [(timestamp: Double, type: String)] = []
  var dominantColors: [(timestamp: Double, colors: [CIColor])] = []
  var motionIntensities: [(timestamp: Double, intensity: Double)] = []
  var brightnessLevels: [(timestamp: Double, brightness: Double)] = []
  var detectedText: [(timestamp: Double, text: String, confidence: Float)] = []
  var audioLevels: [(timestamp: Double, volume: Double, isSilent: Bool)] = []
  var keyFrames: [(timestamp: Double, image: CIImage)] = []

  init(videoPath: String) {
    self.videoPath = videoPath
    self.asset = AVAsset(url: URL(fileURLWithPath: videoPath))

    loadVideoMetadata()
  }

  private func loadVideoMetadata() {
    // Use semaphore to wait for async asset loading to complete
    // AVAsset loading is asynchronous, but we need metadata immediately for initialization
    let semaphore = DispatchSemaphore(value: 0)
    var loadError: NSError?

    asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) {
      semaphore.signal()  // Signal completion of async loading
    }

    semaphore.wait()  // Block until loading completes

    // Check if loading succeeded - AVAsset can fail to load corrupted or unsupported files
    let durationStatus = asset.statusOfValue(forKey: "duration", error: &loadError)
    let tracksStatus = asset.statusOfValue(forKey: "tracks", error: &loadError)

    guard durationStatus == .loaded && tracksStatus == .loaded else {
      logger.error("Error loading video: \(loadError?.localizedDescription ?? "Unknown error")")
      return
    }

    duration = CMTimeGetSeconds(asset.duration)

    // Get video track info - extract resolution, framerate, and codec details
    guard let track = asset.tracks(withMediaType: .video).first else {
      logger.error("No video track found")
      return
    }

    videoTrack = track
    frameRate = track.nominalFrameRate
    dimensions = track.naturalSize
    totalFrames = Int(duration * Double(frameRate))
  }

  /// Extracts basic video metadata and displays information.
  func analyzeBasicInfo() {
    logger.info("Duration: \(String(format: "%.2f", duration)) seconds")
    logger.info("Frame rate: \(frameRate) fps")
    logger.info("Dimensions: \(Int(dimensions.width)) x \(Int(dimensions.height))")
    logger.info("Total frames: \(totalFrames)")
    logger.info("Format: MP4 (AVFoundation)")
    // Collect statistics
    statisticsCollector.addStatistic(category: "metadata", key: "duration_seconds", value: duration)
    statisticsCollector.addStatistic(category: "metadata", key: "frame_rate_fps", value: frameRate)
    statisticsCollector.addStatistic(
      category: "metadata", key: "width_pixels", value: Int(dimensions.width))
    statisticsCollector.addStatistic(
      category: "metadata", key: "height_pixels", value: Int(dimensions.height))
    statisticsCollector.addStatistic(category: "metadata", key: "total_frames", value: totalFrames)
    statisticsCollector.addStatistic(category: "metadata", key: "video_format", value: "MP4")
  }

  /// Analyzes scene changes and background transitions.
  func analyzeBackgroundChanges() {
    logger.debug("Analyzing background changes...")

    guard let videoTrack = videoTrack else { return }

    let reader = try? AVAssetReader(asset: asset)
    let outputSettings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
    reader?.add(trackOutput)

    guard reader?.startReading() == true else {
      logger.error("Failed to start reading")
      return
    }

    var frameCount = 0
    var previousFrameData: [UInt8]?

    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
      frameCount += 1

      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

      let frameData = extractFrameData(from: pixelBuffer)

      if let previous = previousFrameData {
        let difference = calculateFrameDifference(previous, frameData)
        if difference > 0.15 {
          let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
          backgroundChanges.append((timestamp: timestamp, frame: frameCount))
        }
      }

      previousFrameData = frameData

      if frameCount >= 1000 { break }  // Demo limit
    }

    reader?.cancelReading()

    logger.debug("Found \(backgroundChanges.count) background changes")
  }

  /// Detects and analyzes faces in video frames.
  func analyzeFaces() {
    facesDetected = faceDetector.analyzeFaces()

    // Collect statistics
    let totalFaces = facesDetected.reduce(0) { $0 + $1.count }
    statisticsCollector.addStatistic(
      category: "faces", key: "total_faces_detected", value: totalFaces)
    statisticsCollector.addStatistic(
      category: "faces", key: "frames_with_faces", value: facesDetected.count)
    statisticsCollector.addStatistic(
      category: "faces", key: "average_faces_per_frame",
      value: facesDetected.isEmpty ? 0 : Double(totalFaces) / Double(facesDetected.count))
  }

  /// Identifies scene boundaries and transitions.
  func analyzeScenes() {
    let sceneResults = sceneDetector.detectSceneBoundaries()
    sceneBoundaries = sceneResults.map { (timestamp: $0.timestamp, type: $0.type) }

    // Collect statistics
    statisticsCollector.addStatistic(
      category: "scenes", key: "total_scene_changes", value: sceneBoundaries.count)
    if !sceneBoundaries.isEmpty {
      let avgSceneLength = duration / Double(sceneBoundaries.count + 1)
      statisticsCollector.addStatistic(
        category: "scenes", key: "average_scene_length_seconds", value: avgSceneLength)
    }
  }

  /// Extracts dominant colors from video frames.
  func analyzeColors() {
    let colorResults = colorAnalyzer.analyzeColorPalette()
    dominantColors = colorResults.map { (timestamp: $0.timestamp, colors: $0.dominantColors) }

    // Collect statistics
    statisticsCollector.addStatistic(
      category: "colors", key: "color_analysis_frames", value: dominantColors.count)
    if !dominantColors.isEmpty {
      // Extract color names from the palette data
      let colorNames = Array(Set(colorResults.flatMap { $0.palette.keys }))
      statisticsCollector.addStatistic(
        category: "colors", key: "dominant_colors", value: Array(colorNames.prefix(5)))
    }
  }

  /// Analyzes motion and optical flow between frames.
  func analyzeMotion() {
    let motionResults = motionAnalyzer.analyzeMotion()
    motionIntensities = motionResults.map { (timestamp: $0.timestamp, intensity: $0.intensity) }

    // Collect statistics
    statisticsCollector.addStatistic(
      category: "motion", key: "motion_analysis_frames", value: motionIntensities.count)
    if !motionIntensities.isEmpty {
      let avgMotion =
        motionIntensities.map { $0.intensity }.reduce(0, +) / Double(motionIntensities.count)
      statisticsCollector.addStatistic(
        category: "motion", key: "average_motion_intensity", value: avgMotion)
      let maxMotion = motionIntensities.map { $0.intensity }.max() ?? 0
      statisticsCollector.addStatistic(
        category: "motion", key: "maximum_motion_intensity", value: maxMotion)
    }
  }

  /// Measures brightness levels throughout the video.
  func analyzeBrightness() {
    logger.debug("Analyzing brightness levels...")

    guard let videoTrack = videoTrack else { return }

    let reader = try? AVAssetReader(asset: asset)
    let outputSettings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
    reader?.add(trackOutput)

    guard reader?.startReading() == true else { return }

    var frameCount = 0

    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
      frameCount += 1

      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

      let brightness = calculateBrightness(from: pixelBuffer)
      let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

      brightnessLevels.append((timestamp: timestamp, brightness: brightness))

      if frameCount >= 100 { break }  // Demo limit
    }

    reader?.cancelReading()

    let avgBrightness =
      brightnessLevels.map { $0.brightness }.reduce(0, +) / Double(brightnessLevels.count)
    logger.debug("Average brightness: \(String(format: "%.2f", avgBrightness))")

    // Collect statistics
    statisticsCollector.addStatistic(
      category: "brightness", key: "brightness_analysis_frames", value: brightnessLevels.count)
    statisticsCollector.addStatistic(
      category: "brightness", key: "average_brightness", value: avgBrightness)
    if !brightnessLevels.isEmpty {
      let minBrightness = brightnessLevels.map { $0.brightness }.min() ?? 0
      let maxBrightness = brightnessLevels.map { $0.brightness }.max() ?? 0
      statisticsCollector.addStatistic(
        category: "brightness", key: "minimum_brightness", value: minBrightness)
      statisticsCollector.addStatistic(
        category: "brightness", key: "maximum_brightness", value: maxBrightness)
    }
  }

  /// Performs optical character recognition on video frames.
  func analyzeText() {
    let textResults = textDetector.detectText()
    detectedText = textResults.map {
      (timestamp: $0.timestamp, text: $0.text, confidence: $0.confidence)
    }

    // Collect statistics
    statisticsCollector.addStatistic(
      category: "text", key: "total_text_detections", value: detectedText.count)
    if !detectedText.isEmpty {
      let uniqueTexts = Set(detectedText.map { $0.text })
      statisticsCollector.addStatistic(
        category: "text", key: "unique_text_elements", value: uniqueTexts.count)
      let avgConfidence =
        detectedText.map { $0.confidence }.reduce(0, +) / Float(detectedText.count)
      statisticsCollector.addStatistic(
        category: "text", key: "average_text_confidence", value: avgConfidence)
    }
  }

  /// Analyzes audio volume and silence detection.
  func analyzeAudio() {
    let audioResults = audioAnalyzer.analyzeAudio()
    audioLevels = audioResults

    // Collect statistics
    statisticsCollector.addStatistic(
      category: "audio", key: "audio_segments_analyzed", value: audioLevels.count)
    if !audioLevels.isEmpty {
      let avgVolume = audioLevels.map { $0.volume }.reduce(0, +) / Double(audioLevels.count)
      statisticsCollector.addStatistic(
        category: "audio", key: "average_volume", value: avgVolume)

      let silentSegments = audioLevels.filter { $0.isSilent }.count
      let silencePercentage = Double(silentSegments) / Double(audioLevels.count) * 100
      statisticsCollector.addStatistic(
        category: "audio", key: "silence_percentage", value: silencePercentage)
    }
  }

  /// Generates representative key frames from the video.
  func generateKeyFrames() {
    logger.debug("Generating key frames...")

    // Extract key frames at regular intervals
    let keyFrameInterval = duration / 10.0  // 10 key frames total

    for i in 0..<10 {
      let timestamp = Double(i) * keyFrameInterval

      guard let frame = extractFrame(at: timestamp) else { continue }
      keyFrames.append((timestamp: timestamp, image: frame))
    }

    logger.debug("Generated \(keyFrames.count) key frames")

    // Collect statistics
    statisticsCollector.addStatistic(
      category: "keyframes", key: "total_keyframes", value: keyFrames.count)
    statisticsCollector.addStatistic(
      category: "keyframes", key: "keyframe_interval_seconds", value: keyFrameInterval)
  }

  // Helper methods

  /// Extracts grayscale pixel data from a video frame for analysis.
  func extractFrameData(from pixelBuffer: CVPixelBuffer) -> [UInt8] {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    var samples = [UInt8]()

    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
      let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
      let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

      for y in stride(from: 0, to: height, by: max(1, height / 10)) {
        for x in stride(from: 0, to: width, by: max(1, width / 10)) {
          let offset = y * bytesPerRow + x * 4
          if offset < bytesPerRow * height {
            let r = buffer[offset + 2]
            let g = buffer[offset + 1]
            let b = buffer[offset]
            samples.append(UInt8((Int(r) + Int(g) + Int(b)) / 3))
          }
        }
      }
    }

    return samples
  }

  /// Calculates the difference between two video frames as a normalized value.
  func calculateFrameDifference(_ frame1: [UInt8], _ frame2: [UInt8]) -> Double {
    var totalDiff = 0
    let count = min(frame1.count, frame2.count)

    for i in 0..<count {
      totalDiff += abs(Int(frame1[i]) - Int(frame2[i]))
    }

    return Double(totalDiff) / Double(count * 255)
  }

  private func extractDominantColors(from image: CIImage) -> [CIColor] {
    // Simple color extraction - in practice you'd use more sophisticated algorithms
    let extent = image.extent
    let centerX = extent.midX
    let centerY = extent.midY

    // Sample colors from different regions
    let samplePoints = [
      CIVector(x: centerX, y: centerY),
      CIVector(x: extent.minX + extent.width * 0.25, y: centerY),
      CIVector(x: extent.maxX - extent.width * 0.25, y: centerY),
      CIVector(x: centerX, y: extent.minY + extent.height * 0.25),
      CIVector(x: centerX, y: extent.maxY - extent.height * 0.25),
    ]

    var colors = [CIColor]()

    for point in samplePoints {
      let filter = CIFilter(
        name: "CIAreaAverage",
        parameters: [
          kCIInputImageKey: image,
          kCIInputExtentKey: CIVector(x: point.x - 1, y: point.y - 1, z: 2, w: 2),
        ])

      if let outputImage = filter?.outputImage,
        let color = extractColor(from: outputImage)
      {
        colors.append(color)
      }
    }

    return colors
  }

  private func extractColor(from image: CIImage) -> CIColor? {
    let context = CIContext()
    let extent = image.extent

    guard let cgImage = context.createCGImage(image, from: extent) else { return nil }

    let bitmapInfo = cgImage.bitmapInfo
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * Int(extent.width)
    let bitsPerComponent = 8

    var pixelData = [UInt8](repeating: 0, count: bytesPerRow * Int(extent.height))

    guard
      let context2 = CGContext(
        data: &pixelData,
        width: Int(extent.width),
        height: Int(extent.height),
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue)
    else { return nil }

    context2.draw(cgImage, in: extent)

    let r = CGFloat(pixelData[0]) / 255.0
    let g = CGFloat(pixelData[1]) / 255.0
    let b = CGFloat(pixelData[2]) / 255.0
    let a = CGFloat(pixelData[3]) / 255.0

    return CIColor(red: r, green: g, blue: b, alpha: a)
  }

  private func calculateBrightness(from pixelBuffer: CVPixelBuffer) -> Double {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    var totalBrightness = 0.0
    var pixelCount = 0

    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
      let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
      let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

      for y in stride(from: 0, to: height, by: max(1, height / 20)) {
        for x in stride(from: 0, to: width, by: max(1, width / 20)) {
          let offset = y * bytesPerRow + x * 4
          if offset < bytesPerRow * height {
            let r = Int(buffer[offset + 2])
            let g = Int(buffer[offset + 1])
            let b = Int(buffer[offset])
            let brightness = (r + g + b) / 3
            totalBrightness += Double(brightness)
            pixelCount += 1
          }
        }
      }
    }

    return pixelCount > 0 ? totalBrightness / Double(pixelCount) / 255.0 : 0.0
  }

  private func extractFrame(at timestamp: Double) -> CIImage? {
    let time = CMTime(seconds: timestamp, preferredTimescale: 600)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true

    do {
      let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
      return CIImage(cgImage: cgImage)
    } catch {
      return nil
    }
  }
}
