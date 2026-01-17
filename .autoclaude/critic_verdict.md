MINOR_ISSUES

## Summary
Reviewed the CaptureService implementation and related models. The code is well-structured, follows ScreenCaptureKit best practices, and all 8 unit tests pass. The implementation correctly handles window enumeration, frame capture via AsyncStream, and permission checking.

## Minor Issues Found

### 1. CIContext created per-frame (Performance)
**File:** `xdouble/Services/CaptureService.swift:260-262`

In `CaptureStreamOutput.stream()`, a new `CIContext()` is created for every frame:
```swift
let ciImage = CIImage(cvImageBuffer: imageBuffer)
let context = CIContext()
guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
```

`CIContext` is expensive to create and should be reused across frames. At 1-2 FPS this is acceptable but wasteful. Should be moved to a property.

### 2. Content rect parsing may fail silently
**File:** `xdouble/Services/CaptureService.swift:267-275`

The code casts `attachment[.contentRect]` to `[String: CGFloat]`:
```swift
if let rectDict = attachment[.contentRect] as? [String: CGFloat] {
```

ScreenCaptureKit may store the content rect differently (as `CGRect` or `[String: Any]` with `NSNumber` values). This cast may fail silently. The fallback to image dimensions prevents crashes but may lose accurate content rect data.

### 3. Sendable conformance with SCWindow
**File:** `xdouble/Services/CaptureService.swift:14-28`

`CaptureWindow` is marked `Sendable` but contains `scWindow: SCWindow`, which is an `NSObject`. While SCWindow is likely thread-safe in practice, this isn't formally guaranteed by the type system.

## What's Working Well

- Clean separation of concerns with `CaptureWindow`, `CapturedFrame`, and `CaptureError` types
- Proper use of `@MainActor` for the service
- AsyncStream-based frame delivery with proper cleanup
- Good error messages in `CaptureError.errorDescription`
- Permission handling with both preflight and request methods
- Window filtering excludes own app's windows
- FPS clamping to reasonable range (0.1-30)
- Tests verify initial state, error descriptions, and basic functionality

## Test Results
All tests pass:
- CaptureServiceTests: 7 tests passed
- xdoubleTests: 1 test passed
- xdoubleUITests: 2 tests passed
- xdoubleUITestsLaunchTests: 2 tests passed (parallel)
