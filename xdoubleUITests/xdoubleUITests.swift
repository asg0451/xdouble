//
//  xdoubleUITests.swift
//  xdoubleUITests
//
//  UI tests for xdouble window picker and related UI elements.
//

import XCTest

final class xdoubleUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Launch Tests

    @MainActor
    func testAppLaunchesSuccessfully() throws {
        // Verify the app launches and shows a window
        XCTAssertTrue(app.windows.count > 0, "App should have at least one window after launch")
    }

    // MARK: - Permission State Tests

    @MainActor
    func testInitialStateShowsPermissionOrWindowPicker() throws {
        // After launch, app should show either permission view or window picker
        // Wait for the UI to settle (permission check takes a moment)
        let permissionDeniedView = app.staticTexts["permissionRequiredTitle"]
        let windowPickerTitle = app.staticTexts["windowPickerTitle"]
        let checkingView = app.staticTexts["Checking permissions..."]
        let emptyStateView = app.staticTexts["noWindowsTitle"]

        // Wait for initial permission check to complete
        let anyContentAppears = NSPredicate { _, _ in
            return permissionDeniedView.exists ||
                   windowPickerTitle.exists ||
                   emptyStateView.exists
        }

        // Give time for permission check
        let expectation = expectation(for: anyContentAppears, evaluatedWith: nil)
        wait(for: [expectation], timeout: 10.0)

        // Verify we're in one of the expected states
        let isPermissionDenied = permissionDeniedView.exists
        let isWindowPickerVisible = windowPickerTitle.exists
        let isEmptyState = emptyStateView.exists

        XCTAssertTrue(
            isPermissionDenied || isWindowPickerVisible || isEmptyState,
            "App should show permission denied view, window picker, or empty state after permission check"
        )
    }

    // MARK: - Permission Denied View Tests

    @MainActor
    func testPermissionDeniedViewShowsRequiredElements() throws {
        // Wait for permission denied view if it appears
        let permissionDeniedView = app.otherElements["permissionDeniedView"]

        // Skip test if permission is granted
        guard permissionDeniedView.waitForExistence(timeout: 5.0) else {
            // Permission is granted, skip this test
            throw XCTSkip("Screen recording permission is granted, skipping permission denied view tests")
        }

        // Verify the permission denied view has all required elements
        XCTAssertTrue(
            app.staticTexts["permissionRequiredTitle"].exists,
            "Permission denied view should show 'Screen Recording Permission Required' title"
        )

        XCTAssertTrue(
            app.buttons["openSystemSettingsButton"].exists,
            "Permission denied view should have 'Open System Settings' button"
        )

        XCTAssertTrue(
            app.buttons["checkAgainButton"].exists,
            "Permission denied view should have 'Check Again' button"
        )
    }

    @MainActor
    func testCheckAgainButtonIsClickable() throws {
        // Wait for permission denied view
        let checkAgainButton = app.buttons["checkAgainButton"]

        guard checkAgainButton.waitForExistence(timeout: 5.0) else {
            throw XCTSkip("Screen recording permission is granted, skipping permission denied button test")
        }

        XCTAssertTrue(checkAgainButton.isEnabled, "Check Again button should be enabled")

        // Click the button and verify no crash
        checkAgainButton.click()

        // Wait a moment for any state change
        sleep(1)

        // App should still be running (window count > 0)
        XCTAssertTrue(app.windows.count > 0, "App should still have windows after clicking Check Again")
    }

    // MARK: - Window Picker View Tests

    @MainActor
    func testWindowPickerShowsRequiredElements() throws {
        // Wait for either window picker or empty state (both indicate permission granted)
        let windowPickerTitle = app.staticTexts["windowPickerTitle"]
        let emptyStateView = app.otherElements["emptyStateView"]

        let pickerOrEmptyAppears = NSPredicate { _, _ in
            return windowPickerTitle.exists || emptyStateView.exists
        }

        let expectation = expectation(for: pickerOrEmptyAppears, evaluatedWith: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10.0)

        guard result == .completed else {
            throw XCTSkip("Screen recording permission not granted, skipping window picker tests")
        }

        // If we see the window picker title, verify its elements
        if windowPickerTitle.exists {
            // Verify title
            XCTAssertTrue(windowPickerTitle.exists, "Window picker should show 'Select a Window' title")

            // Verify subtitle
            XCTAssertTrue(
                app.staticTexts["windowPickerSubtitle"].exists,
                "Window picker should show subtitle"
            )

            // Verify refresh button exists
            XCTAssertTrue(
                app.buttons["refreshWindowsButton"].exists,
                "Window picker should have a Refresh button"
            )
        } else {
            // Empty state should be visible
            XCTAssertTrue(emptyStateView.exists, "Empty state view should be visible when no windows available")
            XCTAssertTrue(
                app.staticTexts["noWindowsTitle"].exists,
                "Empty state should show 'No Windows Available' text"
            )
        }
    }

    @MainActor
    func testRefreshButtonWorks() throws {
        // Wait for window picker
        let refreshButton = app.buttons["refreshWindowsButton"]

        guard refreshButton.waitForExistence(timeout: 10.0) else {
            // Try empty state refresh button
            let emptyRefreshButton = app.buttons["emptyStateRefreshButton"]
            guard emptyRefreshButton.waitForExistence(timeout: 2.0) else {
                throw XCTSkip("Screen recording permission not granted or window picker not visible")
            }

            // Test empty state refresh button
            XCTAssertTrue(emptyRefreshButton.isEnabled, "Empty state refresh button should be enabled")
            emptyRefreshButton.click()

            // Verify app doesn't crash
            sleep(1)
            XCTAssertTrue(app.windows.count > 0, "App should still have windows after refresh")
            return
        }

        // Verify refresh button is enabled
        XCTAssertTrue(refreshButton.isEnabled, "Refresh button should be enabled")

        // Click refresh and verify no crash
        refreshButton.click()

        // Wait for refresh to complete
        sleep(2)

        // Verify app is still responsive (has windows)
        XCTAssertTrue(app.windows.count > 0, "App should still have windows after clicking Refresh")
    }

    @MainActor
    func testWindowGridOrEmptyStateShown() throws {
        // After permission is granted, we should see either window grid or empty state
        let windowGrid = app.scrollViews["windowGridView"]
        let emptyState = app.otherElements["emptyStateView"]
        let windowPickerTitle = app.staticTexts["windowPickerTitle"]

        // First verify we have permission
        guard windowPickerTitle.waitForExistence(timeout: 10.0) || emptyState.waitForExistence(timeout: 2.0) else {
            throw XCTSkip("Screen recording permission not granted")
        }

        // Give time for window loading
        sleep(3)

        // Either window grid or empty state should be visible
        let gridExists = windowGrid.exists
        let emptyExists = emptyState.exists

        XCTAssertTrue(
            gridExists || emptyExists,
            "Window picker should show either window grid or empty state"
        )
    }

    @MainActor
    func testWindowCardsDisplayedWhenWindowsAvailable() throws {
        // Wait for window picker view
        let windowPickerTitle = app.staticTexts["windowPickerTitle"]

        guard windowPickerTitle.waitForExistence(timeout: 10.0) else {
            throw XCTSkip("Screen recording permission not granted")
        }

        // Wait for window loading to complete
        sleep(3)

        // Check for window grid
        let windowGrid = app.scrollViews["windowGridView"]

        if windowGrid.exists {
            // Find any window cards (they have identifiers like "windowCard_123")
            let windowCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'windowCard_'"))

            // Verify at least one window card exists (since we should have windows)
            XCTAssertGreaterThan(
                windowCards.count, 0,
                "Window grid should contain at least one window card when windows are available"
            )

            // Verify the first window card is hittable (visible and interactive)
            if windowCards.count > 0 {
                let firstCard = windowCards.element(boundBy: 0)
                XCTAssertTrue(
                    firstCard.exists,
                    "Window card should exist and be visible"
                )
            }
        } else {
            // Empty state is shown, which means no windows available
            // This is also valid - test passes but note the condition
            let emptyState = app.otherElements["emptyStateView"]
            XCTAssertTrue(
                emptyState.exists,
                "If window grid is not shown, empty state should be visible"
            )
        }
    }

    // MARK: - Window Selection Tests

    @MainActor
    func testWindowCardIsClickable() throws {
        // Wait for window picker
        let windowPickerTitle = app.staticTexts["windowPickerTitle"]

        guard windowPickerTitle.waitForExistence(timeout: 10.0) else {
            throw XCTSkip("Screen recording permission not granted")
        }

        // Wait for windows to load
        sleep(3)

        // Find window cards
        let windowCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'windowCard_'"))

        guard windowCards.count > 0 else {
            throw XCTSkip("No window cards available")
        }

        let firstCard = windowCards.element(boundBy: 0)

        // Verify the window card is enabled and hittable
        XCTAssertTrue(firstCard.isEnabled, "Window card should be enabled")
        XCTAssertTrue(firstCard.isHittable, "Window card should be hittable")
    }

    @MainActor
    func testSelectWindowNavigatesToTranslationView() throws {
        // Wait for window picker
        let windowPickerTitle = app.staticTexts["windowPickerTitle"]

        guard windowPickerTitle.waitForExistence(timeout: 10.0) else {
            throw XCTSkip("Screen recording permission not granted")
        }

        // Wait for windows to load
        sleep(3)

        // Find window cards
        let windowCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'windowCard_'"))

        guard windowCards.count > 0 else {
            throw XCTSkip("No window cards available")
        }

        let firstCard = windowCards.element(boundBy: 0)

        // Click the window card
        firstCard.click()

        // Wait for transition
        sleep(3)

        // After clicking, should transition away from window picker
        // Could be in setup view, translation view, or error view
        let translationSetupView = app.otherElements["translationSetupView"]
        let waitingView = app.otherElements["waitingView"]
        let translationSetupFailedView = app.otherElements["translationSetupFailedView"]

        let leftWindowPicker = translationSetupView.exists ||
                               waitingView.exists ||
                               translationSetupFailedView.exists ||
                               !windowPickerTitle.exists

        XCTAssertTrue(
            leftWindowPicker,
            "Should navigate away from window picker after selecting a window"
        )
    }

    // MARK: - Performance Tests

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
