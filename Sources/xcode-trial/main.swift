// The Swift Programming Language
// https://docs.swift.org/swift-book

import AVFoundation
import CoreImage
import CoreML
import Foundation
import Vision

/// Command-line entry point for the Video Analysis Tool.
/// Performs multimodal video analysis and exports structured JSON results.
/// Usage: swift run xcode-trial <video.mp4>

/// Performs comprehensive multimodal video analysis and exports results to JSON.
///
/// This function orchestrates the complete analysis pipeline, running all specialized
/// analyzers in sequence and collecting results for structured export. It provides
/// progress feedback and handles export errors gracefully.
///
/// - Parameters:
///   - videoPath: Absolute or relative path to the video file to analyze
///   - arguments: Command-line arguments array for configuration options
///
/// Analysis sequence:
/// 1. Basic metadata extraction (duration, resolution, framerate)
/// 2. Background/scene change detection
/// 3. Facial analysis with landmark detection
/// 4. Scene boundary identification
/// 5. Color palette extraction
/// 6. Motion intensity calculation
/// 7. Brightness level tracking
/// 8. Text recognition and OCR
/// 9. Audio volume and silence analysis
/// 10. Key frame generation
/// 11. Statistics aggregation and export
func runFullAnalysis(videoPath: String, arguments: [String]) {
  setupLogging()
  logger.info("Starting comprehensive video analysis...")
  logger.info("Video: \(videoPath)")
  print()

  let analyzer = VideoAnalyzer(videoPath: videoPath)

  // Run all analyses
  analyzer.analyzeBasicInfo()
  analyzer.analyzeBackgroundChanges()
  analyzer.analyzeFaces()
  analyzer.analyzeScenes()
  analyzer.analyzeColors()
  analyzer.analyzeMotion()
  analyzer.analyzeBrightness()
  analyzer.analyzeText()
  analyzer.analyzeAudio()
  analyzer.generateKeyFrames()
  analyzer.printStatistics()

  // Export results
  let exportPath = (arguments[1] as NSString).deletingPathExtension + "_analysis.json"
  do {
    try analyzer.stats.exportToJSON(filePath: exportPath)
  } catch {
    print("⚠️  Warning: Could not export JSON results: \(error.localizedDescription)")
  }

  print("\n✅ Analysis complete!")
  print("📄 Results exported to: \(exportPath)")
}

/// Displays information about the video analysis tool's capabilities.
/// Shows available analysis features without requiring a video file.
func demonstrateCapabilities() {
  print("🎯 Video Analysis Tool Capabilities:")
  print("===================================")
  print()
  print("📊 Basic: Video metadata, duration, resolution, codecs")
  print("🎭 Faces: Detection, landmarks, tracking, speaker ID")
  print("🎬 Scenes: Boundary detection, cuts/fades, segmentation")
  print("🎨 Colors: Dominant palettes, histograms, grading changes")
  print("📸 Frames: Key frame extraction, thumbnails, storyboards")
  print("⚡ Motion: Optical flow, intensity, camera movement")
  print("💡 Brightness: Lighting changes, exposure tracking")
  print("📝 Text: OCR, captions, on-screen text extraction")
  print("🔈 Audio: Volume tracking, silence detection, patterns")
  print("📈 Output: JSON export, comprehensive statistics")
  print()
  print("🔧 Built with: AVFoundation, Vision, Core Image, Core ML")
}

let arguments = CommandLine.arguments

if arguments.count > 1 {
  let videoPath = arguments[1]
  if FileManager.default.fileExists(atPath: videoPath) {
    runFullAnalysis(videoPath: videoPath, arguments: arguments)
  } else {
    print("❌ Error: File does not exist: \(videoPath)")
    print("Usage: \(arguments[0]) <video_file_path>")
    exit(1)
  }
} else {
  demonstrateCapabilities()
}
