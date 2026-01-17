//
//  RealTranslationE2ETests.swift
//  xdoubleUITests
//
//  Real end-to-end integration tests that open actual content in external apps
//  and verify xdouble can capture and translate them.
//

import XCTest
import Vision

final class RealTranslationE2ETests: XCTestCase {

    var app: XCUIApplication!
    var previewApp: XCUIApplication?

    // Path to test image (loaded from UI test bundle)
    var testImagePath: String {
        Bundle(for: type(of: self)).path(forResource: "chinese_screenshot", ofType: "png")!
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        // Close Preview if it was opened
        previewApp?.terminate()
        previewApp = nil
        app = nil
    }

    // MARK: - Helper Methods

    /// Opens the test image in Preview.app using shell command
    private func openImageInPreview() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Preview", testImagePath]
        try process.run()
        process.waitUntilExit()

        // Store reference to Preview for cleanup
        previewApp = XCUIApplication(bundleIdentifier: "com.apple.Preview")

        // Wait for Preview to launch
        sleep(2)
    }

    /// Finds the Preview window card in xdouble's window picker
    private func findPreviewWindowCard() -> XCUIElement? {
        // Refresh windows first
        let refreshButton = app.buttons["refreshWindowsButton"]
        if refreshButton.exists && refreshButton.isHittable {
            refreshButton.click()
            sleep(2)
        }

        // Look for window cards containing "Preview" or the filename
        let windowCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'windowCard_'"))

        for i in 0..<windowCards.count {
            let card = windowCards.element(boundBy: i)
            // Check if card label contains "Preview" or "chinese_screenshot"
            if card.label.contains("Preview") || card.label.contains("chinese_screenshot") {
                return card
            }
        }

        // Fallback: return first card if no Preview-specific one found
        return windowCards.count > 0 ? windowCards.element(boundBy: 0) : nil
    }

    /// Waits for translation view to appear (either waiting for frames or actively translating)
    private func waitForTranslationView(timeout: TimeInterval = 30) -> Bool {
        // The translation view can show various elements depending on state:
        // - waitingView: when pipeline is starting/running but no frames yet
        // - statsPanel: when stats overlay is visible (may be in different element types)
        // - stopButton: toolbar button when pipeline is running
        // - playButton: toolbar button when pipeline is idle (paused)
        let waitingView = app.otherElements["waitingView"]
        let stopButton = app.buttons["stopButton"]
        let playButton = app.buttons["playButton"]

        // First, wait for either the waiting view or stop/play button to appear
        // This indicates we've transitioned to the translation view
        let translationViewAppears = NSPredicate { _, _ in
            return waitingView.exists || stopButton.exists || playButton.exists
        }

        let expectation = expectation(for: translationViewAppears, evaluatedWith: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)

        return result == .completed
    }

    /// Performs OCR on a screenshot to detect English text
    /// - Parameter screenshot: The XCUIScreenshot to analyze
    /// - Returns: Array of detected English text strings
    private func performEnglishOCR(on screenshot: XCUIScreenshot) -> [String] {
        guard let cgImage = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        var detectedTexts: [String] = []
        let semaphore = DispatchSemaphore(value: 0)

        let request = VNRecognizeTextRequest { request, error in
            defer { semaphore.signal() }

            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }

            for observation in observations {
                if let topCandidate = observation.topCandidates(1).first {
                    detectedTexts.append(topCandidate.string)
                }
            }
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        semaphore.wait()

        return detectedTexts
    }

    /// Checks if the detected text contains likely English translations (not just numbers or UI labels)
    private func containsEnglishTranslation(_ texts: [String]) -> Bool {
        // Common English words that would appear in translations
        let englishIndicators = [
            "the", "and", "is", "are", "was", "were", "have", "has", "had",
            "will", "would", "could", "should", "can", "may", "might",
            "this", "that", "these", "those", "what", "which", "who",
            "from", "with", "for", "not", "but", "you", "your"
        ]

        let joinedText = texts.joined(separator: " ").lowercased()

        // Check for common English words
        for indicator in englishIndicators {
            if joinedText.contains(" \(indicator) ") ||
               joinedText.hasPrefix("\(indicator) ") ||
               joinedText.hasSuffix(" \(indicator)") {
                return true
            }
        }

        // Also check if we have multi-word English phrases (3+ words with spaces)
        for text in texts {
            let words = text.split(separator: " ").filter { $0.count > 1 }
            if words.count >= 3 {
                // Check if words are mostly ASCII (English)
                let asciiWords = words.filter { word in
                    String(word).unicodeScalars.allSatisfy { $0.isASCII && $0.value > 64 }
                }
                if asciiWords.count >= 2 {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - E2E Tests

    @MainActor
    func testRealChineseImageTranslation() throws {
        // Step 1: Wait for window picker
        let windowPickerTitle = app.staticTexts["windowPickerTitle"]
        guard windowPickerTitle.waitForExistence(timeout: 10) else {
            throw XCTSkip("Screen recording permission not granted")
        }

        // Step 2: Open chinese_screenshot.png in Preview
        try openImageInPreview()

        // Step 3: Refresh and find the Preview window
        sleep(2) // Give time for window list to update

        guard let previewCard = findPreviewWindowCard() else {
            throw XCTSkip("Could not find Preview window in picker")
        }

        // Step 4: Click to select the Preview window
        XCTAssertTrue(previewCard.isHittable, "Preview window card should be clickable")
        previewCard.click()

        // Step 5: Wait for translation view to appear
        let translationViewAppeared = waitForTranslationView(timeout: 30)
        XCTAssertTrue(translationViewAppeared, "Translation view should appear after selecting window")

        // Step 6: Verify we're in the translation view
        // Could be showing waitingView (waiting for frames) or processing frames
        let waitingView = app.otherElements["waitingView"]
        let stopButton = app.buttons["stopButton"]

        XCTAssertTrue(
            waitingView.exists || stopButton.exists,
            "Should be in translation view (showing waiting view or stop button)"
        )

        // Step 7: Wait for actual frame processing to occur
        // When frames are processed, the waitingView disappears and is replaced by the frame image
        // The stats panel also becomes visible with frame count
        var frameProcessed = false

        // Wait up to 30 seconds for frames to be processed
        for _ in 0..<30 {
            // Check if waitingView is gone (means we're showing actual translated frames)
            let currentWaitingView = app.otherElements["waitingView"]
            if !currentWaitingView.exists {
                frameProcessed = true
                break
            }

            // Also check for stats panel which shows frame count
            // Try different element types since SwiftUI can map differently
            let statsAsOther = app.otherElements["statsPanel"]
            let statsAsGroup = app.groups["statsPanel"]
            if statsAsOther.exists || statsAsGroup.exists {
                // Stats visible means translation view is active
                // If waitingView is also gone, we have frames
                if !currentWaitingView.exists {
                    frameProcessed = true
                    break
                }
            }

            sleep(1)
        }

        XCTAssertTrue(frameProcessed, "Frames should be processed (waitingView should disappear)")

        // Step 8: Reverse OCR - verify the translated output contains English text
        // Take a screenshot of the translated frame and perform English OCR
        let translatedFrame = app.images["translatedFrameImage"]
        if translatedFrame.waitForExistence(timeout: 5) {
            let screenshot = translatedFrame.screenshot()
            let detectedTexts = performEnglishOCR(on: screenshot)

            // Log detected texts for debugging
            print("Reverse OCR detected texts: \(detectedTexts)")

            // Verify we found English text in the translated output
            let hasEnglishTranslation = containsEnglishTranslation(detectedTexts)
            XCTAssertTrue(
                hasEnglishTranslation,
                "Translated frame should contain English text. Detected: \(detectedTexts)"
            )
        } else {
            // Fallback: take screenshot of the entire window
            let windowScreenshot = app.screenshot()
            let detectedTexts = performEnglishOCR(on: windowScreenshot)
            print("Reverse OCR (window fallback) detected texts: \(detectedTexts)")

            let hasEnglishTranslation = containsEnglishTranslation(detectedTexts)
            XCTAssertTrue(
                hasEnglishTranslation,
                "Translated window should contain English text. Detected: \(detectedTexts)"
            )
        }

        // Step 9: Test stop button functionality
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5), "Stop button should exist while running")
        // Use firstMatch to handle nested button elements
        stopButton.firstMatch.click()

        // Step 10: Verify play button appears after stopping
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 5), "Play button should appear after stopping")

        // Step 11: Test resume - click play button
        playButton.firstMatch.click()

        // Step 12: Verify stop button reappears (translation resumed)
        XCTAssertTrue(stopButton.firstMatch.waitForExistence(timeout: 10), "Stop button should reappear after resuming")
    }

    // TODO: Add test with animated content (video/GIF in browser, scrolling content)
    // to verify continuous frame processing and translation updates
}
