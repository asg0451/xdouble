# Status

**Current Step:** coder
**TODO #:** 3
**Current TODO:** COMPLETED - **Implement CaptureService** - Completion: CaptureService can enumerate available windows and capture frames from a selected window at configurable FPS; unit test passes with mock content
**Goal:** in this newly-initialized swiftui xcode project called xdouble, i want to create an app that can live translate a stream of video from another app's window. my use case is using iphone mirroring to stream an app in another language to the mac running the program - then the program will have another window showing the contents of the app but with text translated (like google translate does for screenshots). i have never written a mac app before so please try extra hard to catch errors as i probably won't. i also have never dealt with live video in place text translation before so dont know the state of the art there. i would prefer something local but would be willing to use an api or smth if required. i'm also prepared to make sacrifices on the translated frame rate if necessary. it should support only simplified mandarin for now, at 1-2 fps.
**Test Command:** whatever is standard for swiftui and configured in this project. make sure to include a verifiable e2e integration test

## Latest Update
Completed: **Implement CaptureService**

Created:
- `xdouble/Services/CaptureService.swift` - Full ScreenCaptureKit wrapper with:
  - `CaptureWindow` struct for representing available windows
  - `CapturedFrame` struct for captured frame data
  - `CaptureError` enum with descriptive error messages
  - `CaptureService` class with window enumeration, streaming capture, and single frame capture
  - Permission checking via `hasScreenRecordingPermission()` and `requestScreenRecordingPermission()`
  - Async stream support for continuous frame capture at configurable FPS
- `xdoubleTests/CaptureServiceTests.swift` - Unit tests covering:
  - CapturedFrame computed properties
  - CaptureError descriptions
  - CaptureService initial state
  - Permission method existence
  - Window lookup functionality

All tests pass. Build succeeds.
