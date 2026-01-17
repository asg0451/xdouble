//
//  TranslationPipelineTests.swift
//  xdoubleTests
//
//  Partial E2E integration tests for the translation pipeline.
//  Tests OCR → filter → render flow without actual translation
//  (TranslationSession API requires UI context).
//

import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import xdouble

@MainActor
struct TranslationPipelineTests {

    // MARK: - Helper Methods

    /// Creates a test image with Chinese text drawn on it.
    /// - Parameters:
    ///   - text: The text to draw
    ///   - size: The image size (defaults to 400x200)
    /// - Returns: A CGImage with the text drawn, or nil if creation failed
    private func createTestImage(withText text: String, size: CGSize = CGSize(width: 400, height: 200)) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
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

    /// Converts CGImage to NSImage
    private func toNSImage(_ cgImage: CGImage) -> NSImage {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Compares two CGImages to check if they're different
    private func imagesAreDifferent(_ image1: CGImage, _ image2: CGImage) -> Bool {
        guard image1.width == image2.width,
              image1.height == image2.height else {
            return true
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return false
        }

        let bytesPerPixel = 4
        let width = image1.width
        let height = image1.height
        let bytesPerRow = bytesPerPixel * width
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        var data1 = [UInt8](repeating: 0, count: height * bytesPerRow)
        var data2 = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context1 = CGContext(
            data: &data1,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ),
              let context2 = CGContext(
                  data: &data2,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo
              ) else {
            return false
        }

        context1.draw(image1, in: CGRect(x: 0, y: 0, width: width, height: height))
        context2.draw(image2, in: CGRect(x: 0, y: 0, width: width, height: height))

        return data1 != data2
    }

    // MARK: - Partial E2E Integration Tests

    @Test func partialE2EPipeline_OCRToFilterToRender() async throws {
        // Step 1: Create a test image with Chinese text
        guard let testImage = createTestImage(withText: "你好世界") else {
            Issue.record("Failed to create test image")
            return
        }

        // Step 2: Run OCR to detect text regions
        let ocrService = OCRService()
        let detectedRegions = try await ocrService.detectText(in: testImage)

        // Verify OCR found some text
        #expect(!detectedRegions.isEmpty, "OCR should detect text in the test image")

        // Step 3: Filter regions to determine which should be translated
        let textFilter = TextFilter(minimumConfidence: 0.3)
        let regionsToTranslate = textFilter.filter(detectedRegions)

        // We may or may not have regions to translate depending on detection confidence
        // The test should pass either way

        // Step 4: Simulate translation by adding mock translations
        // (TranslationSession API requires UI context and can't be used in unit tests)
        var translatedRegions: [TextRegion] = []
        for region in regionsToTranslate {
            var translatedRegion = TextRegion(
                id: region.id,
                text: region.text,
                boundingBox: region.boundingBox,
                confidence: region.confidence,
                translation: "Hello World"  // Mock translation
            )
            translatedRegions.append(translatedRegion)
        }

        // Step 5: Render the translated text onto the image
        let renderer = OverlayRenderer()
        let nsImage = toNSImage(testImage)
        let renderedImage = try renderer.render(regions: translatedRegions, onto: nsImage)

        // Step 6: Verify the output image is valid
        #expect(renderedImage.size.width > 0, "Rendered image should have valid width")
        #expect(renderedImage.size.height > 0, "Rendered image should have valid height")

        // Step 7: If we had regions to translate, verify the image changed
        if !translatedRegions.isEmpty {
            guard let renderedCGImage = renderedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                Issue.record("Failed to get CGImage from rendered image")
                return
            }

            let different = imagesAreDifferent(testImage, renderedCGImage)
            #expect(different, "Output image should differ from input when translations are rendered")
        }
    }

    @Test func partialE2E_withMultipleTextRegions() async throws {
        // Create a larger image that can hold multiple text regions
        guard let testImage = createTestImage(withText: "测试 翻译 系统", size: CGSize(width: 600, height: 200)) else {
            Issue.record("Failed to create test image")
            return
        }

        // Run OCR
        let ocrService = OCRService()
        let detectedRegions = try await ocrService.detectText(in: testImage)

        #expect(!detectedRegions.isEmpty, "OCR should detect text in the test image")

        // Filter regions
        let textFilter = TextFilter(minimumConfidence: 0.3)
        let filteredRegions = textFilter.filter(detectedRegions)

        // Add mock translations
        var translatedRegions: [TextRegion] = []
        for (index, region) in filteredRegions.enumerated() {
            let mockTranslation = ["Test", "Translation", "System"][index % 3]
            translatedRegions.append(TextRegion(
                id: region.id,
                text: region.text,
                boundingBox: region.boundingBox,
                confidence: region.confidence,
                translation: mockTranslation
            ))
        }

        // Render
        let renderer = OverlayRenderer()
        let nsImage = toNSImage(testImage)
        let renderedImage = try renderer.render(regions: translatedRegions, onto: nsImage)

        // Verify rendering completed successfully
        #expect(renderedImage.size.width == CGFloat(testImage.width))
        #expect(renderedImage.size.height == CGFloat(testImage.height))
    }

    @Test func partialE2E_filterRemovesInvalidRegions() async throws {
        // Create test image
        guard let testImage = createTestImage(withText: "你好") else {
            Issue.record("Failed to create test image")
            return
        }

        // Run OCR
        let ocrService = OCRService()
        let detectedRegions = try await ocrService.detectText(in: testImage)

        // Create a strict filter
        let strictFilter = TextFilter(minimumConfidence: 0.99)
        let strictlyFiltered = strictFilter.filter(detectedRegions)

        // Create a lenient filter
        let lenientFilter = TextFilter(minimumConfidence: 0.1)
        let lenientlyFiltered = lenientFilter.filter(detectedRegions)

        // Strict filter should filter out more (or equal) regions than lenient
        #expect(strictlyFiltered.count <= lenientlyFiltered.count,
                "Strict filter should not return more regions than lenient filter")
    }

    @Test func partialE2E_rendererHandlesEmptyRegions() async throws {
        // Create test image
        guard let testImage = createTestImage(withText: "测试") else {
            Issue.record("Failed to create test image")
            return
        }

        // Render with empty regions (should return unchanged image)
        let renderer = OverlayRenderer()
        let nsImage = toNSImage(testImage)
        let renderedImage = try renderer.render(regions: [], onto: nsImage)

        // Image dimensions should be preserved
        #expect(renderedImage.size.width == CGFloat(testImage.width))
        #expect(renderedImage.size.height == CGFloat(testImage.height))
    }

    @Test func partialE2E_fullPipelineDoesNotThrow() async throws {
        // Create test image with realistic Chinese text
        guard let testImage = createTestImage(withText: "欢迎使用翻译", size: CGSize(width: 500, height: 150)) else {
            Issue.record("Failed to create test image")
            return
        }

        // Run full pipeline (except actual translation)
        let ocrService = OCRService()
        let textFilter = TextFilter()
        let renderer = OverlayRenderer()

        // OCR step
        let detectedRegions = try await ocrService.detectText(in: testImage)

        // Filter step
        let filteredRegions = textFilter.filter(detectedRegions)

        // Mock translation step
        let translatedRegions = filteredRegions.map { region in
            TextRegion(
                id: region.id,
                text: region.text,
                boundingBox: region.boundingBox,
                confidence: region.confidence,
                translation: "Welcome to use translation"
            )
        }

        // Render step
        let nsImage = toNSImage(testImage)
        let outputImage = try renderer.render(regions: translatedRegions, onto: nsImage)

        // Final verification
        #expect(outputImage.size.width > 0)
        #expect(outputImage.size.height > 0)

        // If we had translated regions, image should be different
        if !translatedRegions.isEmpty {
            guard let outputCGImage = outputImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                Issue.record("Failed to get CGImage from output")
                return
            }
            #expect(imagesAreDifferent(testImage, outputCGImage), "Output should differ from input with translations")
        }
    }

    @Test func partialE2E_pipelinePreservesImageDimensions() async throws {
        let sizes: [CGSize] = [
            CGSize(width: 200, height: 100),
            CGSize(width: 800, height: 600),
            CGSize(width: 1920, height: 1080)
        ]

        for size in sizes {
            guard let testImage = createTestImage(withText: "尺寸", size: size) else {
                Issue.record("Failed to create test image of size \(size)")
                continue
            }

            let ocrService = OCRService()
            let textFilter = TextFilter(minimumConfidence: 0.1)
            let renderer = OverlayRenderer()

            let regions = try await ocrService.detectText(in: testImage)
            let filtered = textFilter.filter(regions)

            let translatedRegions = filtered.map { region in
                TextRegion(
                    id: region.id,
                    text: region.text,
                    boundingBox: region.boundingBox,
                    confidence: region.confidence,
                    translation: "Size"
                )
            }

            let nsImage = toNSImage(testImage)
            let output = try renderer.render(regions: translatedRegions, onto: nsImage)

            #expect(output.size.width == size.width, "Width should be preserved for size \(size)")
            #expect(output.size.height == size.height, "Height should be preserved for size \(size)")
        }
    }
}
