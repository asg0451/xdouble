MINOR_ISSUES

## Summary

Reviewed the latest 10 commits implementing the xdouble translation pipeline:
- TranslationPipeline actor orchestrating capture → OCR → filter → translate → render flow
- CaptureService for ScreenCaptureKit window capture
- OCRService for Vision framework Chinese text detection
- TranslationService for Apple Translation framework integration
- OverlayRenderer for CoreGraphics text overlay composition
- TextFilter for smart text filtering
- WindowPickerView and TranslatedWindowView SwiftUI components
- ContentView main layout with proper state management

## Test Results

All 63 unit tests pass:
- TextFilterTests (20 tests) - comprehensive filter logic coverage
- OCRServiceTests (11 tests) - OCR with actual Chinese text detection
- OverlayRendererTests (15 tests) - rendering and image comparison
- TranslationServiceTests (10 tests) - service configuration and cache
- CaptureServiceTests (7 tests) - capture service state and types

## What Works Well

1. **Architecture**: Clean separation of concerns following the plan.md design
2. **Swift 6 Concurrency**: Proper use of @MainActor, Sendable, and actors
3. **Error Handling**: Comprehensive error types with LocalizedError conformance
4. **Edge Cases**: Filters handle numbers, single chars, English text, low confidence
5. **Security**: Sandboxed with proper screen recording entitlement
6. **Coordinate Systems**: Correctly handles Vision/CoreGraphics bottom-left origin

## Minor Issues

1. **Missing E2E Integration Test**: The plan.md Phase 6 specifies a TranslationPipeline integration test that loads a test image, runs the full pipeline, and verifies output via OCR re-scan. This test doesn't exist yet. The limitation is understandable since TranslationSession can only be created via SwiftUI's `.translationTask` modifier, making pure unit testing difficult. However, a partial E2E test could verify OCR→filter→render without actual translation.
