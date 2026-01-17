# TODOs

## In Progress

## Pending

- [x] **Fix: Add partial E2E integration test** - Completion: TranslationPipelineTests.swift exists with a test that loads a test image, runs OCR→filter→render (without actual translation due to TranslationSession API limitation), and verifies output image differs from input and rendering completed without error
  - Priority: low

- [x] **Fix: Remove unconventional `nonisolated` type prefixes** - Completion: Remove `nonisolated` keyword from type declarations in TextRegion.swift, TextFilter.swift, OCRService.swift, and OverlayRenderer.swift. Types should just conform to `Sendable` without the `nonisolated` prefix, which is the conventional approach.
  - Priority: low

- [x] **Fix: Add meaningful UI tests** - Completion: xdoubleUITests.swift contains tests that verify window picker UI elements exist, refresh button works, and window cards are displayed when windows are available
  - Priority: low

- [x] **Fix: Swift 6 concurrency warnings** - Completion: Resolve MainActor isolation warnings in OCRService and TextRegion so the code compiles without warnings in Swift 6 language mode
  - Priority: low

- [x] **Fix: Reuse CIContext in CaptureStreamOutput** - Completion: CIContext is stored as a property in CaptureStreamOutput and reused across stream callback invocations instead of being created per-frame
  - Priority: low

- [x] **Fix: Correct content rect type cast in CaptureStreamOutput** - Completion: The attachment[.contentRect] cast uses the correct type (likely CGRect or NSDictionary) and successfully extracts content rect values
  - Priority: low

- [x] **Fix: Consider CaptureWindow Sendable conformance** - Completion: Either remove Sendable conformance from CaptureWindow, use @unchecked Sendable with documentation explaining safety, or copy only the necessary data from SCWindow
  - Priority: low

### Phase 1: Project Setup & Foundation

- [x] **Configure entitlements for screen recording** - Completion: xdouble.entitlements file exists with com.apple.security.screen-recording key set to true, and project.pbxproj references it
  - Priority: high
  - Dependencies: none

- [x] **Create data models** - Completion: TextRegion.swift and TranslatedFrame.swift exist with documented structs that compile without errors
  - Priority: high
  - Dependencies: none

### Phase 2: Core Services

- [x] **Implement CaptureService** - Completion: CaptureService can enumerate available windows and capture frames from a selected window at configurable FPS; unit test passes with mock content
  - Priority: high
  - Dependencies: Configure entitlements

- [x] **Implement OCRService** - Completion: OCRService.detectText(in:) returns array of TextRegion with Chinese text and bounding boxes; unit test with sample Chinese image passes
  - Priority: high
  - Dependencies: Create data models

- [x] **Implement TranslationService** - Completion: TranslationService.translate(_:) converts Chinese text to English; unit test with known phrase "你好" → "Hello" (or similar) passes
  - Priority: high
  - Dependencies: none

- [x] **Implement smart text filtering** - Completion: TextFilter.shouldTranslate(_:) returns false for numbers-only, single chars, low-confidence, and English text; all filter unit tests pass
  - Priority: medium
  - Dependencies: Create data models

- [x] **Implement OverlayRenderer** - Completion: OverlayRenderer.render(regions:onto:) produces NSImage with translated text overlaid; visual inspection test or pixel comparison test passes
  - Priority: high
  - Dependencies: Create data models

### Phase 3: Pipeline Integration

- [x] **Implement TranslationPipeline actor** - Completion: TranslationPipeline.start(window:) orchestrates capture→OCR→filter→translate→render flow; publishes TranslatedFrame via Combine/AsyncSequence
  - Priority: high
  - Dependencies: CaptureService, OCRService, TranslationService, OverlayRenderer

### Phase 4: User Interface

- [x] **Implement WindowPickerView** - Completion: SwiftUI view displays list of available windows with thumbnails; selecting a window triggers callback with SCWindow
  - Priority: high
  - Dependencies: CaptureService (for window enumeration)

- [x] **Implement TranslatedWindowView** - Completion: SwiftUI view displays TranslatedFrame images; updates at frame rate from pipeline
  - Priority: high
  - Dependencies: TranslationPipeline

- [x] **Update ContentView with main layout** - Completion: ContentView shows WindowPickerView when no window selected, TranslatedWindowView when active; stop button works
  - Priority: high
  - Dependencies: WindowPickerView, TranslatedWindowView

- [x] **Update xdoubleApp for proper windowing** - Completion: App launches correctly, handles window lifecycle, shows permission dialogs when needed
  - Priority: high
  - Dependencies: ContentView

### Phase 5: Error Handling & Polish

- [x] **Add screen recording permission handling** - Completion: App detects missing permission and shows alert with "Open System Settings" button that opens correct pane
  - Priority: high
  - Dependencies: CaptureService

- [x] **Add translation model download handling** - Completion: App handles case where translation model isn't downloaded; shows appropriate UI feedback
  - Priority: medium
  - Dependencies: TranslationService

- [x] **Add loading states and feedback** - Completion: UI shows loading indicator while initializing; shows "Processing..." or frame rate indicator during operation
  - Priority: medium
  - Dependencies: ContentView, TranslationPipeline

### Phase 6: Testing

- [x] **Add test assets (Chinese text images)** - Completion: Test bundle contains at least 2 PNG images with clear Chinese text for testing
  - Priority: high
  - Dependencies: none

- [x] **Write OCRService unit tests** - Completion: Tests in xdoubleTests verify OCR detects Chinese text in test image with correct bounding boxes
  - Priority: high
  - Dependencies: OCRService, test assets

- [x] **Write TranslationService unit tests** - Completion: Tests verify translation of known Chinese phrases returns English
  - Priority: high
  - Dependencies: TranslationService

- [x] **Write TextFilter unit tests** - Completion: Tests cover all filter conditions (numbers, single char, low confidence, English text)
  - Priority: medium
  - Dependencies: Text filtering implementation

- [ ] **Write OverlayRenderer unit tests** - Completion: Tests verify rendered output dimensions match input; output differs from input when text regions provided
  - Priority: medium
  - Dependencies: OverlayRenderer

- [ ] **Write TranslationPipeline integration test (E2E)** - Completion: Test loads test image from bundle, runs full pipeline (OCR→filter→translate→render), verifies output contains English text via OCR re-scan; this is the verifiable E2E test
  - Priority: high
  - Dependencies: All services, pipeline, test assets

### Phase 7: Build Verification

- [ ] **Verify app builds and runs** - Completion: `xcodebuild -scheme xdouble build` succeeds; app launches without crash
  - Priority: high
  - Dependencies: All implementation tasks

- [ ] **Verify all tests pass** - Completion: `xcodebuild test -scheme xdouble -destination 'platform=macOS'` passes all unit and integration tests
  - Priority: high
  - Dependencies: All test tasks

## Completed

## Notes

- Test images for OCR testing can be created programmatically or added as static assets
- Translation framework may require language pack download on first use - tests should handle this gracefully
- Screen capture tests may need to be marked as requiring user interaction or use mock data
- The E2E integration test uses a static test image rather than live capture to avoid permission issues in CI
