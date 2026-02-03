# Video Analysis Tool

A comprehensive Swift-based video analysis tool that performs multimodal analysis on video files, extracting insights about faces, scenes, colors, motion, audio, text, and more. Perfect for content analysis, video classification, and ML feature extraction.

## 🎯 Overview

This tool analyzes MP4 video files and generates detailed JSON reports containing:

- **Face Detection**: Face counting, landmark analysis, and presence tracking
- **Scene Analysis**: Scene boundary detection, transition analysis, and pacing metrics
- **Color Analysis**: Dominant color palette extraction and color consistency tracking
- **Motion Analysis**: Optical flow calculation and motion intensity measurement
- **Audio Analysis**: Volume level tracking, silence detection, and speaking pattern estimation
- **Text Detection**: OCR text extraction with confidence scoring
- **Brightness Analysis**: Lighting consistency and exposure tracking
- **Keyframe Extraction**: Representative frame selection for video thumbnails

## 🚀 Key Features

- **Multimodal Analysis**: Combines computer vision, audio processing, and metadata extraction
- **High Performance**: Optimized algorithms for fast processing of long videos
- **JSON Export**: Structured output perfect for ML pipelines and data analysis
- **Modular Architecture**: Easily extensible with new analysis components
- **Production Ready**: Built with Swift Package Manager, supports both debug and release builds

## 📋 Requirements

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

## 🔮 Future Projects

See [ROLES.md](ROLES.md) for detailed perspectives on potential enhancements from Data Engineer, Spark/Flink Engineer, AI/ML Engineer, and AI/LLM Engineer viewpoints.
