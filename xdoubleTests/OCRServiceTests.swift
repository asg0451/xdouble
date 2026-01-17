//
//  OCRServiceTests.swift
//  xdoubleTests
//
//  Tests for OCRService Chinese text detection.
//

import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import xdouble

struct OCRServiceTests {

    // MARK: - Helper Methods

    /// Creates a test image with Chinese text drawn on it
    /// - Parameters:
    ///   - text: The text to draw
    ///   - size: The image size (defaults to 400x200)
    /// - Returns: A CGImage with the text drawn, or nil if creation failed
    private func createTestImage(withText text: String, size: CGSize = CGSize(width: 400, height: 200)) -> CGImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        // Fill with white background
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        // Draw text in black
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))

        // Use a system font that supports Chinese characters
        let font = NSFont.systemFont(ofSize: 48)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)

        // Calculate text bounds for centering
        let textBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let xOffset = (size.width - textBounds.width) / 2
        let yOffset = (size.height - textBounds.height) / 2

        // Draw the text
        context.textPosition = CGPoint(x: xOffset, y: yOffset)
        CTLineDraw(line, context)

        return context.makeImage()
    }

    // MARK: - OCRError Tests

    @Test func ocrErrorDescriptions() async throws {
        #expect(OCRError.imageCreationFailed.errorDescription != nil)
        #expect(OCRError.imageCreationFailed.errorDescription!.contains("Failed to create image"))

        #expect(OCRError.noTextFound.errorDescription != nil)
        #expect(OCRError.noTextFound.errorDescription!.contains("No text"))

        let underlyingError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "test error"])
        let requestError = OCRError.requestFailed(underlyingError)
        #expect(requestError.errorDescription != nil)
        #expect(requestError.errorDescription!.contains("Text recognition failed"))
    }

    // MARK: - OCRService Initialization Tests

    @Test func ocrServiceDefaultInitialization() async throws {
        let service = OCRService()

        #expect(service.minimumConfidence == 0.0)
        #expect(service.recognitionLanguages == ["zh-Hans"])
    }

    @Test func ocrServiceCustomInitialization() async throws {
        let service = OCRService(minimumConfidence: 0.5, recognitionLanguages: ["en-US", "zh-Hans"])

        #expect(service.minimumConfidence == 0.5)
        #expect(service.recognitionLanguages == ["en-US", "zh-Hans"])
    }

    // MARK: - Text Detection Tests

    @Test func detectTextInChineseImage() async throws {
        let service = OCRService()

        // Create test image with Chinese text
        guard let testImage = createTestImage(withText: "你好世界") else {
            Issue.record("Failed to create test image")
            return
        }

        let regions = try await service.detectText(in: testImage)

        // Verify we got at least one text region
        #expect(!regions.isEmpty, "Should detect text in the image")

        // Verify the detected text contains Chinese characters
        let allText = regions.map { $0.text }.joined()
        let containsChinese = allText.contains { char in
            char.unicodeScalars.contains { scalar in
                // CJK Unified Ideographs range
                (0x4E00...0x9FFF).contains(scalar.value) ||
                // CJK Unified Ideographs Extension A
                (0x3400...0x4DBF).contains(scalar.value)
            }
        }
        #expect(containsChinese, "Detected text should contain Chinese characters, got: \(allText)")
    }

    @Test func detectTextReturnsBoundingBoxes() async throws {
        let service = OCRService()

        guard let testImage = createTestImage(withText: "测试文本") else {
            Issue.record("Failed to create test image")
            return
        }

        let regions = try await service.detectText(in: testImage)

        for region in regions {
            // Bounding boxes should be in normalized coordinates (0.0-1.0)
            #expect(region.boundingBox.origin.x >= 0 && region.boundingBox.origin.x <= 1)
            #expect(region.boundingBox.origin.y >= 0 && region.boundingBox.origin.y <= 1)
            #expect(region.boundingBox.width > 0 && region.boundingBox.width <= 1)
            #expect(region.boundingBox.height > 0 && region.boundingBox.height <= 1)
        }
    }

    @Test func detectTextReturnsConfidenceScores() async throws {
        let service = OCRService()

        guard let testImage = createTestImage(withText: "信心测试") else {
            Issue.record("Failed to create test image")
            return
        }

        let regions = try await service.detectText(in: testImage)

        for region in regions {
            // Confidence should be between 0 and 1
            #expect(region.confidence >= 0.0 && region.confidence <= 1.0)
        }
    }

    @Test func detectTextRespectsMinimumConfidence() async throws {
        // Create service with high minimum confidence
        let service = OCRService(minimumConfidence: 0.99)

        guard let testImage = createTestImage(withText: "你好") else {
            Issue.record("Failed to create test image")
            return
        }

        let regions = try await service.detectText(in: testImage)

        // All returned regions should meet the minimum confidence
        for region in regions {
            #expect(region.confidence >= 0.99)
        }
    }

    @Test func detectTextInCapturedFrame() async throws {
        let service = OCRService()

        guard let testImage = createTestImage(withText: "框架测试") else {
            Issue.record("Failed to create test image")
            return
        }

        let frame = CapturedFrame(
            image: testImage,
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 200),
            captureTime: Date()
        )

        let regions = try await service.detectText(in: frame)

        #expect(!regions.isEmpty, "Should detect text in the captured frame")
    }

    @Test func detectTextWithNoTextInImage() async throws {
        let service = OCRService()

        // Create a blank image with no text
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create test context")
            return
        }

        // Fill with solid color (no text)
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))

        guard let blankImage = context.makeImage() else {
            Issue.record("Failed to create blank image")
            return
        }

        let regions = try await service.detectText(in: blankImage)

        // Should return empty array (not throw) when no text is found
        #expect(regions.isEmpty, "Should return empty array for image with no text")
    }

    // MARK: - Supported Languages Test

    @Test func supportedLanguagesIncludesChinese() async throws {
        let languages = OCRService.supportedLanguages()

        let hasChineseSupport = languages.contains { lang in
            lang.hasPrefix("zh")
        }

        #expect(hasChineseSupport, "System should support Chinese text recognition")
    }

    // MARK: - TextRegion Integration Tests

    @Test func textRegionAbsoluteBoundingBoxConversion() async throws {
        let service = OCRService()

        guard let testImage = createTestImage(withText: "坐标转换") else {
            Issue.record("Failed to create test image")
            return
        }

        let regions = try await service.detectText(in: testImage)
        guard let region = regions.first else {
            Issue.record("No text regions detected")
            return
        }

        let imageSize = CGSize(width: testImage.width, height: testImage.height)
        let absoluteBox = region.absoluteBoundingBox(for: imageSize)

        // Absolute coordinates should be within image bounds
        #expect(absoluteBox.origin.x >= 0)
        #expect(absoluteBox.origin.y >= 0)
        #expect(absoluteBox.maxX <= imageSize.width)
        #expect(absoluteBox.maxY <= imageSize.height)
        #expect(absoluteBox.width > 0)
        #expect(absoluteBox.height > 0)
    }
}
