import AVFoundation
import Foundation

/// Analyzes audio tracks in video files to extract volume levels and silence detection.
class AudioAnalyzer: VideoReaderObserver {
  private let videoAnalyzer: VideoAnalyzer
  var results: [(timestamp: Double, volume: Double, isSilent: Bool)] = []

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
  }

  func processAudio(_ result: AudioResult) {
    results.append((
      timestamp: result.timestamp,
      volume: result.volume,
      isSilent: result.isSilent
    ))
  }
}
