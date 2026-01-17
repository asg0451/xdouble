//
//  CaptureServiceTests.swift
//  xdoubleTests
//
//  Tests for CaptureService and related types.
//

import Testing
import Foundation
import CoreGraphics
@testable import xdouble

struct CaptureServiceTests {

    // MARK: - CapturedFrame Tests

    @Test func capturedFrameSizeComputedProperty() async throws {
        // Create a test CGImage (1x1 red pixel)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: 100,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            Issue.record("Failed to create test CGContext")
            return
        }

        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))

        guard let cgImage = context.makeImage() else {
            Issue.record("Failed to create test CGImage")
            return
        }

        let frame = CapturedFrame(
            image: cgImage,
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 200),
            captureTime: Date()
        )

        #expect(frame.size.width == 100)
        #expect(frame.size.height == 200)
    }

    @Test func capturedFrameCaptureTime() async throws {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: 10,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
              let cgImage = context.makeImage() else {
            Issue.record("Failed to create test image")
            return
        }

        let captureTime = Date()
        let frame = CapturedFrame(
            image: cgImage,
            contentRect: CGRect.zero,
            captureTime: captureTime
        )

        #expect(frame.captureTime == captureTime)
    }

    // MARK: - CaptureError Tests

    @Test func captureErrorDescriptions() async throws {
        #expect(CaptureError.permissionDenied.errorDescription != nil)
        #expect(CaptureError.permissionDenied.errorDescription!.contains("Screen recording permission"))

        #expect(CaptureError.noWindowsAvailable.errorDescription != nil)
        #expect(CaptureError.noWindowsAvailable.errorDescription!.contains("No windows"))

        #expect(CaptureError.windowNotFound.errorDescription != nil)
        #expect(CaptureError.windowNotFound.errorDescription!.contains("no longer available"))

        #expect(CaptureError.streamCreationFailed.errorDescription != nil)
        #expect(CaptureError.streamCreationFailed.errorDescription!.contains("Failed to create"))

        #expect(CaptureError.frameCaptureFailed.errorDescription != nil)
        #expect(CaptureError.frameCaptureFailed.errorDescription!.contains("Failed to capture"))

        #expect(CaptureError.invalidConfiguration.errorDescription != nil)
        #expect(CaptureError.invalidConfiguration.errorDescription!.contains("Invalid"))
    }

    @Test func captureErrorConformsToLocalizedError() async throws {
        let error: any LocalizedError = CaptureError.permissionDenied
        #expect(error.errorDescription != nil)
    }

    // MARK: - CaptureService Tests

    @Test @MainActor func captureServiceInitialState() async throws {
        let service = CaptureService()

        #expect(service.availableWindows.isEmpty)
        #expect(service.isCapturing == false)
        #expect(service.selectedWindow == nil)
        #expect(service.framesPerSecond == 1.0)
    }

    @Test @MainActor func captureServiceHasPermissionMethodExists() async throws {
        // Just verify the static method can be called without crashing
        // The actual result depends on system permissions
        _ = CaptureService.hasScreenRecordingPermission()
    }

    @Test @MainActor func captureServiceWindowLookup() async throws {
        let service = CaptureService()

        // With no windows loaded, lookup should return nil
        let result = service.window(withID: 12345)
        #expect(result == nil)
    }
}
