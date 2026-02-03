# Video Analysis Tool

A comprehensive Swift-based video analysis tool that performs multimodal analysis on video files, extracting insights about faces, scenes, colors, motion, audio, text, and more. Perfect for content analysis, video classification, and ML feature extraction.

See [AGENTS.md](AGENTS.md) for information about AI agent integration and development workflows.

See [ROLES.md](ROLES.md) for engineering perspectives and data flow architecture.

## 🚀 Key Features

- **Multimodal Analysis**: Combines computer vision, audio processing, and metadata extraction
- **High Performance**: Optimized algorithms for fast processing of long videos
- **JSON Export**: Structured output perfect for ML pipelines and data analysis
- **Modular Architecture**: Easily extensible with new analysis components
- **Production Ready**: Built with Swift Package Manager, supports both debug and release builds

## ⌨️ Requirements

- **macOS 12.0+**
- **Xcode 13.0+** or Swift 5.5+
- **AVFoundation** (built-in)
- **Vision Framework** (built-in)
- **Core Image** (built-in)

## 🛠️ Installation & Building

### Development Build (with debug symbols)
```bash
git clone <repository-url>
cd video-analysis-tool
swift build
```

### Production Build (optimized)
```bash
swift build --configuration release
```

### Running the Tool
```bash
# Development build
.build/debug/xcode-trial /path/to/your/video.mp4

# Production build
.build/release/xcode-trial /path/to/your/video.mp4
```

## 🎯 Example Output

```json
{
  "metadata": {
    "duration_seconds": 14.97,
    "frame_rate_fps": 30.0,
    "width_pixels": 1080,
    "height_pixels": 1920,
    "video_format": "MP4"
  },
  "faces": {
    "total_faces_detected": 296,
    "average_faces_per_frame": 1.13,
    "frames_with_faces": 262
  },
  "scenes": {
    "total_scene_changes": 11,
    "average_scene_length_seconds": 1.25
  },
  "audio": {
    "average_volume": 25.3,
    "silence_percentage": 0.0,
    "audio_segments_analyzed": 100
  },
  "text": {
    "total_text_detections": 65,
    "unique_text_elements": 21,
    "average_text_confidence": 1.0
  }
}
```
