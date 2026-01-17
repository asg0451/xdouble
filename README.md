# xdouble

Real-time Chinese-to-English translation overlay for any macOS window.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-green)
![Swift](https://img.shields.io/badge/Swift-5-orange)

## What it does

xdouble captures any window on your Mac, detects Chinese text using Vision OCR, translates it to English using Apple's on-device Translation framework, and overlays the translated text directly on top of the original—all in real-time at ~1.5 fps.

Perfect for:
- Translating Chinese apps via iPhone Mirroring
- Reading Chinese content in any application
- Following along with Chinese videos or streams

## Features

- **Live translation overlay** — See translations directly on top of the original text
- **Window picker** — Select any window on your Mac to translate
- **Fully on-device** — Uses Apple's Translation framework, no internet required after initial model download
- **Smart text filtering** — Skips numbers, single characters, and already-English text
- **Translation caching** — LRU cache avoids re-translating repeated text
- **Pan & zoom** — Navigate translated content with gestures
- **Performance stats** — Optional overlay showing frame timing and region counts

## Requirements

- macOS 15.0 (Sequoia) or later
- Apple Silicon Mac
- Screen Recording permission (prompted on first launch)

## Installation

### Build from source

```bash
git clone https://github.com/asg0451/xdouble.git
cd xdouble
xcodebuild -scheme xdouble build
```

The built app will be in `~/Library/Developer/Xcode/DerivedData/xdouble-*/Build/Products/Debug/xdouble.app`

### Run tests

```bash
# All tests
xcodebuild -scheme xdouble -destination 'platform=macOS' test

# Unit tests only
xcodebuild -scheme xdouble -destination 'platform=macOS' test -only-testing:xdoubleTests
```

## Usage

1. **Launch xdouble** — Grant Screen Recording permission when prompted
2. **Wait for translation model** — First launch downloads Apple's Chinese→English model (~50MB)
3. **Select a window** — Click any window thumbnail in the picker
4. **View translations** — The translated overlay appears automatically

### Controls

| Action | Control |
|--------|---------|
| Pause/Resume | Play/Stop button in toolbar |
| Toggle stats | `S` key or stats button |
| Zoom | Pinch gesture or scroll |
| Pan | Drag when zoomed |
| Change window | Back button in toolbar |

## Architecture

```
ContentView (UI + permission flow)
    ↓
TranslationPipeline (@MainActor orchestrator)
    ├── CaptureService (ScreenCaptureKit → AsyncStream<CapturedFrame>)
    ├── OCRService (Vision framework → [TextRegion])
    ├── TextFilter (skip numbers, English, low-confidence)
    ├── TranslationService (Apple Translation + LRU cache)
    └── OverlayRenderer (CoreGraphics text composition)
    ↓
TranslatedWindowView (displays translated frames)
```

## Privacy

xdouble runs entirely on your device:
- Screen capture stays local
- Translation uses Apple's on-device ML model
- No data is sent to any server
- No analytics or telemetry

## License

MIT

## Acknowledgments

Built with Apple frameworks:
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) for window capture
- [Vision](https://developer.apple.com/documentation/vision) for OCR
- [Translation](https://developer.apple.com/documentation/translation) for on-device translation
- [SwiftUI](https://developer.apple.com/documentation/swiftui) for the interface
