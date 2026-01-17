MINOR_ISSUES

## Summary

Reviewed the complete implementation of xdouble - a macOS app for live translating video streams from another app's window. The codebase includes:

- **Services**: CaptureService (ScreenCaptureKit), OCRService (Vision), TranslationService (Apple Translation), OverlayRenderer (CoreGraphics), TextFilter
- **Pipeline**: TranslationPipeline actor orchestrating the capture → OCR → translate → render flow
- **Views**: WindowPickerView, TranslatedWindowView, ContentView
- **Models**: TextRegion, TranslatedFrame
- **Tests**: 70+ unit tests all passing

## Verdict

**Build**: PASSES (no errors)
**Tests**: ALL PASS (70+ tests)
**Security**: No vulnerabilities found
**Architecture**: Follows plan.md correctly

## Minor Issues

### 1. Missing E2E Integration Test

The plan.md explicitly specifies a `TranslationPipelineIntegrationTests` E2E test that should:
1. Load a test image with Chinese text from test bundle
2. Run through OCR → translate → render pipeline
3. Verify output image is different from input
4. Verify translated text appears in output (via secondary OCR pass)

This test was not implemented. While unit tests cover individual components well, the full pipeline integration test is missing.

### 2. Swift 6 Concurrency Warnings

The build shows warnings about MainActor isolation that will become errors in Swift 6 language mode:
- OCRService is marked `Sendable` but some callers would need `await` for MainActor isolation
- TextRegion's `absoluteBoundingBox(for:)` appears MainActor-isolated to callers

These don't prevent the code from working but should be addressed for Swift 6 compatibility.

## What Works Well

- Clean separation of concerns with dedicated services for each task
- Proper async/await usage throughout
- Good error handling with descriptive error types
- TranslationCache actor for efficient caching
- Smart text filtering (numbers, single chars, English text, low confidence)
- Background color sampling for readable text overlay
- Comprehensive unit test coverage
- Proper entitlements for screen recording
