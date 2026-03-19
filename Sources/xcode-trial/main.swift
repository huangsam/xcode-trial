// The Swift Programming Language
// https://docs.swift.org/swift-book

import AVFoundation
import CoreImage
import Foundation
import Logging
import Vision

/// Sets up the logging system with a stdout backend for command-line output.
func setupLogging() {
  LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = .info
    return handler
  }
}

/// Global logger instance for the video analysis tool.
let logger = Logging.Logger(label: "com.xcode-trial.video-analysis")

/// Performs comprehensive multimodal video analysis and exports results to JSON.
func runFullAnalysis(videoPath: String, arguments: [String]) {
  setupLogging()
  logger.info("Starting comprehensive video analysis...")
  logger.info("Video: \(videoPath)")

  let analyzer = VideoAnalyzer(videoPath: videoPath)

  // Run the optimized single-pass analysis
  analyzer.runAnalysis()

  // Export results
  let exportPath = (arguments[1] as NSString).deletingPathExtension + "_analysis.json"
  do {
    try analyzer.stats.exportToJSON(filePath: exportPath)
  } catch {
    logger.warning("Warning: Could not export JSON results: \(error.localizedDescription)")
  }

  logger.info("Analysis complete!")
}

let arguments = CommandLine.arguments

if arguments.count > 1 {
  let videoPath = arguments[1]
  if FileManager.default.fileExists(atPath: videoPath) {
    runFullAnalysis(videoPath: videoPath, arguments: arguments)
  }
} else {
  print("Usage: swift run xcode-trial <video.mp4>")
}
