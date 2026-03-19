import AVFoundation
import CoreImage
import Foundation
import Vision

class VideoAnalyzer {
  let videoPath: String
  let asset: AVAsset
  var videoTrack: AVAssetTrack?
  var audioTrack: AVAssetTrack?
  var duration: Double = 0
  var frameRate: Float = 0
  var dimensions: CGSize = .zero
  var totalFrames: Int = 0

  // Specialized analyzers
  lazy var faceDetector = FaceDetector(videoAnalyzer: self)
  lazy var sceneDetector = SceneDetector(videoAnalyzer: self)
  lazy var colorAnalyzer = ColorAnalyzer(videoAnalyzer: self)
  lazy var motionAnalyzer = MotionAnalyzer(videoAnalyzer: self)
  lazy var textDetector = TextDetector(videoAnalyzer: self)
  lazy var audioAnalyzer = AudioAnalyzer(videoAnalyzer: self)
  lazy var statisticsCollector = StatisticsCollector()

  // Internal observers for simple metrics
  private class BrightnessObserver: VideoReaderObserver {
    var videoInterval: Int { 10 }
    var brightnessLevels: [(timestamp: Double, brightness: Double)] = []
    func processFrame(_ result: FrameResult) {
      let brightness = calculateBrightness(from: result.pixelBuffer)
      brightnessLevels.append((timestamp: result.timestamp, brightness: brightness))
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
            let r = Int(buffer[offset + 2]), g = Int(buffer[offset + 1]), b = Int(buffer[offset])
            totalBrightness += Double(r + g + b) / 3.0
            pixelCount += 1
          }
        }
      }
      return pixelCount > 0 ? totalBrightness / Double(pixelCount) / 255.0 : 0.0
    }
  }

  private let brightnessObserver = BrightnessObserver()

  var stats: StatisticsCollector { statisticsCollector }

  init(videoPath: String) {
    self.videoPath = videoPath
    self.asset = AVAsset(url: URL(fileURLWithPath: videoPath))
    loadVideoMetadata()
  }

  private func loadVideoMetadata() {
    let semaphore = DispatchSemaphore(value: 0)
    asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) {
      semaphore.signal()
    }
    semaphore.wait()

    duration = CMTimeGetSeconds(asset.duration)
    videoTrack = asset.tracks(withMediaType: .video).first
    audioTrack = asset.tracks(withMediaType: .audio).first

    if let track = videoTrack {
      frameRate = track.nominalFrameRate
      dimensions = track.naturalSize
      totalFrames = Int(duration * Double(frameRate))
    }
  }

  func runAnalysis() {
    logger.info("Starting optimized single-pass video analysis...")
    
    let reader = VideoReader(asset: asset, videoTrack: videoTrack, audioTrack: audioTrack)
    
    // Register all analyzers as observers
    reader.addObserver(faceDetector)
    reader.addObserver(sceneDetector)
    reader.addObserver(colorAnalyzer)
    reader.addObserver(motionAnalyzer)
    reader.addObserver(textDetector)
    reader.addObserver(audioAnalyzer)
    reader.addObserver(brightnessObserver)
    
    do {
      try reader.readAll()
    } catch {
      logger.error("Analysis failed: \(error.localizedDescription)")
    }
    
    collectFinalStatistics()
  }

  private func collectFinalStatistics() {
    // Metadata
    stats.addStatistic(category: "metadata", key: "duration", value: duration)
    stats.addStatistic(category: "metadata", key: "dimensions", value: "\(Int(dimensions.width))x\(Int(dimensions.height))")
    
    // Faces
    stats.addStatistic(category: "faces", key: "frames_with_faces", value: faceDetector.results.count)
    
    // Scenes
    stats.addStatistic(category: "scenes", key: "total_scenes", value: sceneDetector.sceneBoundaries.count)
    
    // Motion
    if !motionAnalyzer.motionData.isEmpty {
      let avgMotion = motionAnalyzer.motionData.map { $0.intensity }.reduce(0, +) / Double(motionAnalyzer.motionData.count)
      stats.addStatistic(category: "motion", key: "average_intensity", value: avgMotion)
    }
    
    // Brightness
    if !brightnessObserver.brightnessLevels.isEmpty {
      let avgBrightness = brightnessObserver.brightnessLevels.map { $0.brightness }.reduce(0, +) / Double(brightnessObserver.brightnessLevels.count)
      stats.addStatistic(category: "brightness", key: "average_brightness", value: avgBrightness)
    }
    
    // Audio
    if !audioAnalyzer.results.isEmpty {
      let avgVolume = audioAnalyzer.results.map { $0.volume }.reduce(0, +) / Double(audioAnalyzer.results.count)
      stats.addStatistic(category: "audio", key: "average_volume", value: avgVolume)
    }
  }

  // Keep this for the scene detector to use
  func calculateFrameDifference(_ frame1: [UInt8], _ frame2: [UInt8]) -> Double {
    let count = min(frame1.count, frame2.count)
    if count == 0 { return 0 }
    var totalDiff = 0
    for i in 0..<count {
      totalDiff += abs(Int(frame1[i]) - Int(frame2[i]))
    }
    return Double(totalDiff) / Double(count * 255)
  }
  
  // Legacy stubs for main.swift compatibility if needed
  func analyzeBasicInfo() { logger.info("Metadata loaded.") }
  func analyzeBackgroundChanges() {}
  func analyzeFaces() {}
  func analyzeScenes() {}
  func analyzeColors() {}
  func analyzeMotion() {}
  func analyzeBrightness() {}
  func analyzeText() {}
  func analyzeAudio() {}
  func generateKeyFrames() {}
}
