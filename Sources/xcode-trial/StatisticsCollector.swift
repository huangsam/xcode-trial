import Foundation

class StatisticsCollector {
  private var statistics: [String: Any] = [:]

  func addStatistic(category: String, key: String, value: Any) {
    if statistics[category] == nil {
      statistics[category] = [String: Any]()
    }

    if var categoryDict = statistics[category] as? [String: Any] {
      categoryDict[key] = value
      statistics[category] = categoryDict
    }
  }

  func getStatistic(category: String, key: String) -> Any? {
    guard let categoryDict = statistics[category] as? [String: Any] else { return nil }
    return categoryDict[key]
  }

  func getCategoryStatistics(category: String) -> [String: Any]? {
    return statistics[category] as? [String: Any]
  }

  func getAllStatistics() -> [String: [String: Any]] {
    var result = [String: [String: Any]]()
    for (category, data) in statistics {
      if let dict = data as? [String: Any] {
        result[category] = dict
      }
    }
    return result
  }

  func generateReport() -> String {
    var report = "📊 Video Analysis Report\n"
    report += "========================\n\n"

    let categories = [
      "metadata", "faces", "scenes", "colors", "motion", "brightness", "text", "audio", "keyframes",
    ]

    for category in categories {
      if let categoryStats = getCategoryStatistics(category: category) {
        report += "📋 \(category.capitalized) Analysis:\n"

        for (key, value) in categoryStats.sorted(by: { $0.key < $1.key }) {
          let formattedKey = key.replacingOccurrences(of: "_", with: " ").capitalized
          report += "  • \(formattedKey): \(formatValue(value))\n"
        }
        report += "\n"
      }
    }

    // Add summary insights
    report += "💡 Key Insights:\n"
    report += generateInsights()

    return report
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

  func exportToJSON(filePath: String) throws {
    let jsonData = try JSONSerialization.data(withJSONObject: statistics, options: .prettyPrinted)
    try jsonData.write(to: URL(fileURLWithPath: filePath))
    print("📄 Analysis results exported to: \(filePath)")
  }

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
    print("📊 Analysis results exported to CSV: \(filePath)")
  }
}
