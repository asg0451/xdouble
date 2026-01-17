# Status

**Current Step:** coder
**TODO #:** 12
**Current TODO:** **Implement WindowPickerView** - Completion: SwiftUI view displays list of available windows with thumbnails; selecting a window triggers callback with SCWindow
**Goal:** in this newly-initialized swiftui xcode project called xdouble, i want to create an app that can live translate a stream of video from another app's window. my use case is using iphone mirroring to stream an app in another language to the mac running the program - then the program will have another window showing the contents of the app but with text translated (like google translate does for screenshots). i have never written a mac app before so please try extra hard to catch errors as i probably won't. i also have never dealt with live video in place text translation before so dont know the state of the art there. i would prefer something local but would be willing to use an api or smth if required. i'm also prepared to make sacrifices on the translated frame rate if necessary. it should support only simplified mandarin for now, at 1-2 fps.
**Test Command:** whatever is standard for swiftui and configured in this project. make sure to include a verifiable e2e integration test

## Latest Update
Completed: **Implement TranslationPipeline actor**

The TranslationPipeline is now implemented in `xdouble/Pipeline/TranslationPipeline.swift`. It orchestrates the full translation flow:
- Captures frames from a selected window via CaptureService
- Detects text via OCRService
- Filters non-translatable content via TextFilter
- Translates Chinese to English via TranslationService
- Renders translated text overlays via OverlayRenderer
- Publishes TranslatedFrame via AsyncStream for UI consumption
- Includes translation caching for performance
- Tracks statistics (frame count, average processing time)

All existing tests pass (68 tests total).
