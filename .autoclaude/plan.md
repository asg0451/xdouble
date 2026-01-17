# Implementation Plan: xdouble

## Overview

xdouble is a macOS app that captures another app's window (primarily iPhone Mirroring), performs OCR to detect Chinese text, translates it to English using Apple's on-device Translation framework, and displays the result with translated text overlaid on the original image.

**Target:** macOS 15+ (Sequoia), 1-2 fps translation rate, Simplified Chinese → English only.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        xdoubleApp                               │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐     ┌─────────────────────────────────┐   │
│  │  Source Window  │     │      Translated Window          │   │
│  │  (Picker UI)    │     │      (Output Display)           │   │
│  └────────┬────────┘     └──────────────▲──────────────────┘   │
│           │                             │                       │
│           ▼                             │                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              TranslationPipeline (Actor)                 │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐  │   │
│  │  │ Capture  │→ │   OCR    │→ │Translate │→ │ Render  │  │   │
│  │  │ Service  │  │ Service  │  │ Service  │  │ Service │  │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └─────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Core Components

1. **WindowPickerView** - SwiftUI view to list and select available windows
2. **CaptureService** - ScreenCaptureKit wrapper for window capture
3. **OCRService** - Vision framework wrapper for Chinese text detection
4. **TranslationService** - Apple Translation framework wrapper
5. **OverlayRenderer** - CoreGraphics-based text overlay compositor
6. **TranslationPipeline** - Coordinates the capture→OCR→translate→render flow
7. **TranslatedWindowView** - Displays the final output

## Key Decisions

### 1. ScreenCaptureKit for Window Capture
- Modern API (macOS 12.3+), designed for this exact use case
- `SCShareableContent` to enumerate windows
- `SCStream` with `SCStreamConfiguration` for frame capture
- Set frame rate to 1-2 fps via `minimumFrameInterval`

### 2. Vision Framework for OCR
- `VNRecognizeTextRequest` with `.accurate` recognition level
- Set `recognitionLanguages = ["zh-Hans"]` for Simplified Chinese
- Returns `VNRecognizedTextObservation` with bounding boxes and confidence

### 3. Apple Translation Framework
- `TranslationSession` with source: `.chineseSimplified`, target: `.english`
- Fully on-device, no API keys needed
- May require one-time language model download

### 4. Smart Text Filtering
Skip translation for:
- Pure numbers (regex: `^\d+$`)
- Single characters
- Very low confidence OCR results (< 0.5)
- Already-English text (detected via character range)

### 5. Best-Effort Text Overlay
- Sample background color from region around text
- Calculate font size based on bounding box height
- Use system font with appropriate weight
- Center text within original bounding box

### 6. Pipeline as Swift Actor
- Ensures thread-safe state management
- Async/await for clean flow control
- Cancellation support for when user changes source window

## Data Flow

```
1. User selects window from picker
2. CaptureService starts SCStream at 1 fps
3. For each frame:
   a. OCRService extracts text regions with bounds
   b. Filter out non-translatable content
   c. TranslationService translates Chinese → English
   d. OverlayRenderer composites translated text on frame
   e. TranslatedWindowView displays result
4. Repeat until user stops or changes window
```

## Files to Create/Modify

### New Files

| File | Purpose |
|------|---------|
| `Services/CaptureService.swift` | ScreenCaptureKit wrapper, window enumeration and streaming |
| `Services/OCRService.swift` | Vision framework OCR for Chinese text |
| `Services/TranslationService.swift` | Apple Translation framework wrapper |
| `Services/OverlayRenderer.swift` | CoreGraphics text overlay composition |
| `Pipeline/TranslationPipeline.swift` | Orchestrates the full translation flow |
| `Models/TextRegion.swift` | Data model for detected text with bounds |
| `Models/TranslatedFrame.swift` | Output frame with metadata |
| `Views/WindowPickerView.swift` | Window selection UI |
| `Views/TranslatedWindowView.swift` | Output display view |
| `Views/SettingsView.swift` | FPS and other settings (minimal for MVP) |
| `xdouble.entitlements` | Screen recording entitlement |

### Modified Files

| File | Changes |
|------|---------|
| `xdoubleApp.swift` | Add WindowGroup for translated output, app lifecycle |
| `ContentView.swift` | Main UI with window picker and translated view |

## Entitlements Required

```xml
<key>com.apple.security.screen-recording</key>
<true/>
```

The app will need to be granted Screen Recording permission in System Settings > Privacy & Security.

## Testing Strategy

### Unit Tests (xdoubleTests)
- `OCRServiceTests` - Test OCR with sample images containing Chinese text
- `TranslationServiceTests` - Test translation of known phrases
- `OverlayRendererTests` - Test text rendering produces valid images
- `TextFilterTests` - Test smart filtering logic

### UI Tests (xdoubleUITests)
- Test window picker UI elements exist
- Test settings controls work

### Integration Test (E2E)
- `TranslationPipelineIntegrationTests` - Full pipeline test using a test image:
  1. Load a test image with Chinese text from test bundle
  2. Run through OCR → translate → render pipeline
  3. Verify output image is different from input
  4. Verify translated text appears in output (via secondary OCR pass)

This provides verifiable E2E testing without requiring actual screen capture permissions.

## Performance Considerations

- Frame rate limited to 1-2 fps to allow time for OCR + translation
- Translation results can be cached by source text hash
- Pipeline should drop frames if processing takes longer than frame interval
- Use background priority for non-UI work

## Error Handling

1. **No screen recording permission**: Show alert with button to open System Settings
2. **Translation model not downloaded**: Prompt user to download via Translation settings
3. **No windows available**: Show helpful message
4. **OCR fails**: Show original frame without translation

## Future Enhancements (Out of Scope for MVP)
- Additional language pairs
- Adjustable frame rate
- Region-of-interest selection
- Translation caching across sessions
- Export translated frames
