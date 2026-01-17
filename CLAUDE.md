# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

xdouble is a macOS app that provides real-time Chinese→English translation overlay for any window. It captures a target window (e.g., iPhone Mirroring), performs OCR to detect Chinese text, translates using Apple's on-device Translation framework, and renders translated text overlaid on the original image at ~1.5 fps.

**Requirements:** macOS 15+ (Sequoia), Apple Silicon, Screen Recording permission

## Build & Test Commands

```bash
# Build
xcodebuild -scheme xdouble build

# Run all tests
xcodebuild -scheme xdouble -destination 'platform=macOS' test

# Run specific test class
xcodebuild -scheme xdouble -destination 'platform=macOS' test -only-testing:xdoubleTests/TranslationPipelineTests

# Run specific test method
xcodebuild -scheme xdouble -destination 'platform=macOS' test -only-testing:xdoubleTests/TranslationPipelineTests/testStartCreatesFrameStream

# Run UI tests only
xcodebuild -scheme xdouble -destination 'platform=macOS' test -only-testing:xdoubleUITests

# Run E2E test (requires screen recording permission)
xcodebuild -scheme xdouble -destination 'platform=macOS' test -only-testing:xdoubleUITests/RealTranslationE2ETests
```

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
TranslatedWindowView (displays AsyncStream<TranslatedFrame>)
```

**Key types:**
- `TextRegion` - Detected text with normalized bounding box and confidence
- `TranslatedFrame` - Output image with overlay, timing metrics, region data
- `PipelineState` - enum: idle, starting, running, stopping, error(String)

## Key Files

| Path | Purpose |
|------|---------|
| `Pipeline/TranslationPipeline.swift` | Main orchestrator, frame processing loop |
| `Services/CaptureService.swift` | ScreenCaptureKit wrapper, window enumeration |
| `Services/OCRService.swift` | Vision framework Chinese text detection |
| `Services/TranslationService.swift` | Translation + actor-based LRU cache |
| `Services/TextFilter.swift` | Filters regions to skip (numbers, English, single chars) |
| `Services/OverlayRenderer.swift` | CoreGraphics text rendering with background sampling |
| `ContentView.swift` | Main view, permission checks, translation model setup |
| `Views/WindowPickerView.swift` | Grid UI for selecting source window |
| `Views/TranslatedWindowView.swift` | Displays translated frames with stats overlay |

## Data Flow

1. User grants screen recording permission
2. User selects target window from picker
3. TranslationService checks/downloads translation model
4. CaptureService streams frames at 1.5 fps
5. Per frame: OCR → Filter → Translate (cached) → Render overlay
6. TranslatedWindowView displays result with performance stats

## Testing

- **Unit tests** (`xdoubleTests/`): Test services with mocks, comprehensive pipeline tests
- **UI tests** (`xdoubleUITests/`): Flow testing, real E2E with actual images
- **Test images**: `xdoubleTests/Resources/chinese_screenshot.png`

## Concurrency Model

- `TranslationPipeline` is `@MainActor` for UI binding
- `TranslationCache` is an `actor` for thread-safe caching
- Services are `Sendable`
- Frame delivery via `AsyncStream`

## No External Dependencies

Uses only Apple frameworks: SwiftUI, ScreenCaptureKit, Vision, Translation, CoreGraphics

## Development Guidelines

**Never declare a task complete until the project builds.** Always run `xcodebuild -scheme xdouble build` to verify changes compile before considering any implementation finished.
