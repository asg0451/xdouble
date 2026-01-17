# Status

**Current Step:** coder
**TODO #:** 1
**Current TODO:** **Configure entitlements for screen recording** - Completion: xdouble.entitlements file exists with com.apple.security.screen-recording key set to true, and project.pbxproj references it
**Goal:** in this newly-initialized swiftui xcode project called xdouble, i want to create an app that can live translate a stream of video from another app's window. my use case is using iphone mirroring to stream an app in another language to the mac running the program - then the program will have another window showing the contents of the app but with text translated (like google translate does for screenshots). i have never written a mac app before so please try extra hard to catch errors as i probably won't. i also have never dealt with live video in place text translation before so dont know the state of the art there. i would prefer something local but would be willing to use an api or smth if required. i'm also prepared to make sacrifices on the translated frame rate if necessary. it should support only simplified mandarin for now, at 1-2 fps.
**Test Command:** whatever is standard for swiftui and configured in this project. make sure to include a verifiable e2e integration test

## Latest Update
Completed: **Configure entitlements for screen recording**
- Created xdouble/xdouble.entitlements with com.apple.security.screen-recording = true
- Added CODE_SIGN_ENTITLEMENTS reference to project.pbxproj (Debug and Release)
- Build verified successful
