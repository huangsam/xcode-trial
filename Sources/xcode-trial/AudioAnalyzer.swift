import AVFoundation
import Foundation

class AudioAnalyzer {
  private let videoAnalyzer: VideoAnalyzer

  init(videoAnalyzer: VideoAnalyzer) {
    self.videoAnalyzer = videoAnalyzer
  }

  func analyzeAudio() -> [(timestamp: Double, volume: Double, isSilent: Bool)] {
    print("🔊 Performing audio analysis...")

    // Get audio tracks
    let audioTracks = videoAnalyzer.asset.tracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else {
      print("  ⚠️  No audio tracks found")
      return []
    }

    let audioTrack = audioTracks[0]
    print("  📊 Audio format: \(audioTrack.mediaType.rawValue)")
    print("  🎵 Sample rate: \(audioTrack.naturalTimeScale) Hz")
    print("  📏 Channels: \(audioTrack.naturalSize.width)")

    // Create audio reader
    let reader = try? AVAssetReader(asset: videoAnalyzer.asset)
    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]

    let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
    reader?.add(trackOutput)

    guard reader?.startReading() == true else {
      print("  ❌ Could not start audio reading")
      return []
    }

    var audioData: [(timestamp: Double, volume: Double, isSilent: Bool)] = []
    var sampleCount = 0
    let _ = 44100 / 10  // Analyze 10 times per second (placeholder for future use)

    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
      guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

      let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

      // Get audio data
      var length = 0
      var dataPointer: UnsafeMutablePointer<Int8>?
      guard
        CMBlockBufferGetDataPointer(
          blockBuffer, atOffset: 0, lengthAtOffsetOut: &length, totalLengthOut: nil,
          dataPointerOut: &dataPointer) == noErr
      else { continue }

      if let audioBytes = dataPointer {
        // Create Data from the buffer
        let data = Data(bytes: audioBytes, count: length)

        // Calculate RMS volume from 16-bit PCM data
        var sum: Double = 0
        var sampleCount = 0

        // Process 16-bit samples (2 bytes each)
        for i in stride(from: 0, to: data.count, by: 2) {
          if i + 1 < data.count {
            let lowByte = data[i]
            let highByte = data[i + 1]
            let sample = Int16(lowByte) | (Int16(highByte) << 8)
            let normalizedSample = Double(sample) / 32768.0
            sum += normalizedSample * normalizedSample
            sampleCount += 1
          }
        }

        if sampleCount > 0 {
          let rms = sqrt(sum / Double(sampleCount))
          let volume = min(rms * 100, 100)  // Scale to 0-100
          let isSilent = volume < 1.0  // Threshold for silence

          audioData.append((timestamp: timestamp, volume: volume, isSilent: isSilent))
        }
      }

      sampleCount += 1
      if sampleCount >= 100 { break }  // Demo limit
    }

    reader?.cancelReading()

    print("  ✅ Analyzed audio in \(audioData.count) segments")

    // Analyze audio patterns
    analyzeAudioPatterns(audioData)

    return audioData
  }

  private func analyzeAudioPatterns(
    _ audioData: [(timestamp: Double, volume: Double, isSilent: Bool)]
  ) {
    if audioData.isEmpty { return }

    let avgVolume = audioData.map { $0.volume }.reduce(0, +) / Double(audioData.count)
    let silentSegments = audioData.filter { $0.isSilent }.count
    let silencePercentage = Double(silentSegments) / Double(audioData.count) * 100

    print("  🎚️  Audio analysis results:")
    print("    Average volume: \(String(format: "%.1f", avgVolume))%")
    print("    Silent segments: \(silentSegments) (\(String(format: "%.1f", silencePercentage))%)")

    // Detect volume changes
    var volumeChanges = 0
    for i in 1..<audioData.count {
      if abs(audioData[i].volume - audioData[i - 1].volume) > 20 {  // 20% change threshold
        volumeChanges += 1
      }
    }

    if volumeChanges > 0 {
      print("    Volume changes detected: \(volumeChanges)")
    }

    // Analyze speaking patterns (rough approximation)
    let speakingSegments = audioData.filter { $0.volume > 5 }.count
    let speakingPercentage = Double(speakingSegments) / Double(audioData.count) * 100

    if speakingPercentage > 10 {
      print("    Estimated speaking time: \(String(format: "%.1f", speakingPercentage))%")
    }
  }
}
