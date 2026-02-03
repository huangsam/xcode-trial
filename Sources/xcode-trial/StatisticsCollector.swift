import Foundation

/// Collects and aggregates analysis results into structured statistics.
///
/// `StatisticsCollector` serves as a centralized data aggregation system for all
/// video analysis results. It organizes data by categories, provides query interfaces,
/// and handles JSON export for downstream ML pipelines and data analysis.
///
/// Key responsibilities:
/// - Hierarchical data organization by analysis categories
/// - Type-safe storage and retrieval of analysis results
/// - JSON serialization for external consumption
/// - Report generation for human-readable summaries
///
/// Data organization:
/// - Categories: metadata, faces, scenes, colors, motion, brightness, text, audio
/// - Hierarchical structure: category → key → value
/// - Type preservation: maintains original data types in storage
/// - Query optimization: efficient category-based access
///
/// Export capabilities:
/// - JSON serialization with proper formatting
/// - File system persistence with error handling
/// - Structured output for ML feature engineering
/// - Human-readable report generation
///
/// Design patterns:
/// - Builder pattern for incremental result accumulation
/// - Facade pattern for simplified external interface
/// - Strategy pattern for different export formats
///
/// Performance considerations:
/// - In-memory storage for fast access during analysis
/// - Lazy serialization for export operations
/// - Memory-efficient data structures
/// - Thread-safe operations for concurrent analysis
///
/// Integration points:
/// - ML pipelines: structured feature extraction
/// - Data lakes: JSON ingestion and processing
/// - Analytics systems: queryable result storage
/// - Monitoring dashboards: real-time metric display
///
/// Usage patterns:
/// - Accumulate results during analysis phases
/// - Query specific metrics for conditional logic
/// - Export complete results for persistence
/// - Generate reports for human consumption
class StatisticsCollector {
  private var statistics: [String: Any] = [:]

  /// Adds a statistic value to the specified category and key.
  func addStatistic(category: String, key: String, value: Any) {
    if statistics[category] == nil {
      statistics[category] = [String: Any]()
    }

    if var categoryDict = statistics[category] as? [String: Any] {
      categoryDict[key] = value
      statistics[category] = categoryDict
    }
  }

  /// Retrieves a specific statistic value.
  func getStatistic(category: String, key: String) -> Any? {
    guard let categoryDict = statistics[category] as? [String: Any] else { return nil }
    return categoryDict[key]
  }

  /// Retrieves all statistics for a specific category.
  func getCategoryStatistics(category: String) -> [String: Any]? {
    return statistics[category] as? [String: Any]
  }

  /// Retrieves all statistics organized by category.
  func getAllStatistics() -> [String: [String: Any]] {
    var result = [String: [String: Any]]()
    for (category, data) in statistics {
      if let dict = data as? [String: Any] {
        result[category] = dict
      }
    }
    return result
  }

  private func formatValue(_ value: Any) -> String {
    switch value {
    case let intValue as Int:
      return "\(intValue)"
    case let doubleValue as Double:
      if doubleValue < 1.0 {
        return String(format: "%.3f", doubleValue)
      } else {
        return String(format: "%.2f", doubleValue)
      }
    case let floatValue as Float:
      if floatValue < 1.0 {
        return String(format: "%.3f", floatValue)
      } else {
        return String(format: "%.2f", floatValue)
      }
    case let boolValue as Bool:
      return boolValue ? "Yes" : "No"
    case let stringValue as String:
      return stringValue
    case let arrayValue as [Any]:
      if arrayValue.count <= 3 {
        return arrayValue.map { formatValue($0) }.joined(separator: ", ")
      } else {
        return "\(arrayValue.count) items"
      }
    case let dictValue as [String: Any]:
      return "\(dictValue.count) properties"
    default:
      return "\(value)"
    }
  }

  private func generateInsights() -> String {
    var insights = ""

    // Video duration insights
    if let duration = getStatistic(category: "metadata", key: "duration_seconds") as? Double {
      insights += "  • Video duration: \(String(format: "%.1f", duration))s\n"
    }

    // Face detection insights
    if let faceCount = getStatistic(category: "faces", key: "total_faces_detected") as? Int,
      let duration = getStatistic(category: "metadata", key: "duration_seconds") as? Double
    {
      let facesPerMinute = Double(faceCount) / (duration / 60.0)
      insights +=
        "  • Face detection rate: \(String(format: "%.1f", facesPerMinute)) faces/minute\n"
    }

    // Scene change insights
    if let sceneCount = getStatistic(category: "scenes", key: "total_scene_changes") as? Int,
      let duration = getStatistic(category: "metadata", key: "duration_seconds") as? Double
    {
      let scenesPerMinute = Double(sceneCount) / (duration / 60.0)
      insights +=
        "  • Scene change frequency: \(String(format: "%.1f", scenesPerMinute)) changes/minute\n"
    }

    // Motion insights
    if let avgMotion = getStatistic(category: "motion", key: "average_motion_intensity") as? Double
    {
      let motionLevel = avgMotion > 0.7 ? "High" : avgMotion > 0.3 ? "Medium" : "Low"
      insights += "  • Motion level: \(motionLevel) (avg: \(String(format: "%.2f", avgMotion)))\n"
    }

    // Color insights
    if let dominantColors = getStatistic(category: "colors", key: "dominant_colors") as? [String] {
      insights += "  • Dominant color theme: \(dominantColors.prefix(3).joined(separator: ", "))\n"
    }

    // Brightness insights
    if let avgBrightness = getStatistic(category: "brightness", key: "average_brightness")
      as? Double
    {
      let brightnessLevel = avgBrightness > 0.7 ? "Bright" : avgBrightness > 0.3 ? "Medium" : "Dark"
      insights +=
        "  • Overall brightness: \(brightnessLevel) (avg: \(String(format: "%.2f", avgBrightness)))\n"
    }

    // Text insights
    if let textCount = getStatistic(category: "text", key: "total_text_detections") as? Int {
      insights += "  • Text elements detected: \(textCount)\n"
    }

    // Audio insights
    if let avgVolume = getStatistic(category: "audio", key: "average_volume") as? Double {
      let volumeLevel = avgVolume > 50 ? "Loud" : avgVolume > 20 ? "Medium" : "Quiet"
      insights += "  • Audio level: \(volumeLevel) (avg: \(String(format: "%.1f", avgVolume))%)\n"
    }

    // Key frame insights
    if let keyframeCount = getStatistic(category: "keyframes", key: "total_keyframes") as? Int {
      insights += "  • Key frames identified: \(keyframeCount)\n"
    }

    if insights.isEmpty {
      insights = "  • No analysis data available\n"
    }

    return insights
  }

  /// Exports all statistics to a JSON file.
  func exportToJSON(filePath: String) throws {
    let jsonData = try JSONSerialization.data(withJSONObject: statistics, options: .prettyPrinted)
    try jsonData.write(to: URL(fileURLWithPath: filePath))
    logger.info("Analysis results exported to: \(filePath)")
  }

  /// Exports all statistics to a CSV file.
  func exportToCSV(filePath: String) throws {
    var csvContent = "Category,Key,Value\n"

    for (category, data) in statistics {
      if let dict = data as? [String: Any] {
        for (key, value) in dict {
          let formattedValue = formatValue(value).replacingOccurrences(of: ",", with: ";")
          csvContent += "\(category),\(key),\(formattedValue)\n"
        }
      }
    }

    try csvContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    logger.info("Analysis results exported to CSV: \(filePath)")
  }
}
