//
//  OverlayRendererTests.swift
//  xdoubleTests
//
//  Tests for OverlayRenderer text overlay rendering.
//

import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import xdouble

@MainActor
struct OverlayRendererTests {

    // MARK: - Helper Methods

    /// Creates a simple test image with a solid color using CoreGraphics.
    private func createTestImage(width: Int = 200, height: Int = 100, color: NSColor = .white) -> NSImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            // Fallback to a simple empty image
            return NSImage(size: NSSize(width: width, height: height))
        }

        // Convert NSColor to CGColor
        let rgbColor = color.usingColorSpace(.deviceRGB) ?? .white
        let cgColor = CGColor(
            red: rgbColor.redComponent,
            green: rgbColor.greenComponent,
            blue: rgbColor.blueComponent,
            alpha: rgbColor.alphaComponent
        )

        // Fill with the specified color
        context.setFillColor(cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else {
            return NSImage(size: NSSize(width: width, height: height))
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    /// Creates a TextRegion with translation for testing.
    private func makeRegion(
        text: String,
        translation: String?,
        boundingBox: CGRect = CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.2),
        confidence: Float = 0.9
    ) -> TextRegion {
        TextRegion(
            text: text,
            boundingBox: boundingBox,
            confidence: confidence,
            translation: translation
        )
    }

    // MARK: - Initialization Tests

    @Test func defaultPaddingRatio() async throws {
        let renderer = OverlayRenderer()
        #expect(renderer.paddingRatio == 0.1)
    }

    @Test func customPaddingRatio() async throws {
        let renderer = OverlayRenderer(paddingRatio: 0.2)
        #expect(renderer.paddingRatio == 0.2)
    }

    // MARK: - Basic Rendering Tests

    @Test func renderWithNoRegions() async throws {
        let renderer = OverlayRenderer()
        let sourceImage = createTestImage()

        let result = try renderer.render(regions: [], onto: sourceImage)

        // Output should have same dimensions as input
        #expect(result.size.width == sourceImage.size.width)
        #expect(result.size.height == sourceImage.size.height)
    }

    @Test func renderWithRegionsWithoutTranslation() async throws {
        let renderer = OverlayRenderer()
        let sourceImage = createTestImage()

        let regions = [
            makeRegion(text: "你好", translation: nil),
            makeRegion(text: "世界", translation: nil)
        ]

        let result = try renderer.render(regions: regions, onto: sourceImage)

        // Should succeed and return image of same size
        #expect(result.size.width == sourceImage.size.width)
        #expect(result.size.height == sourceImage.size.height)
    }

    @Test func renderWithTranslatedRegions() async throws {
        let renderer = OverlayRenderer()
        let sourceImage = createTestImage()

        let regions = [
            makeRegion(text: "你好", translation: "Hello")
        ]

        let result = try renderer.render(regions: regions, onto: sourceImage)

        // Should succeed and return image of same size
        #expect(result.size.width == sourceImage.size.width)
        #expect(result.size.height == sourceImage.size.height)
    }

    @Test func renderModifiesImageWhenTranslationPresent() async throws {
        let renderer = OverlayRenderer()
        let sourceImage = createTestImage(color: .blue)

        let regions = [
            makeRegion(
                text: "你好",
                translation: "Hello",
                boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
            )
        ]

        let result = try renderer.render(regions: regions, onto: sourceImage)

        // Get pixel data from both images to compare
        guard let sourceCG = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let resultCG = result.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OverlayRendererError.invalidImage
        }

        // Images should be different (translation text was rendered)
        let imagesAreDifferent = !compareImages(sourceCG, resultCG)
        #expect(imagesAreDifferent, "Rendered image should differ from source when translation is present")
    }

    @Test func renderWithEmptyTranslation() async throws {
        let renderer = OverlayRenderer()
        let sourceImage = createTestImage()

        let regions = [
            makeRegion(text: "你好", translation: "")
        ]

        // Empty translation should be skipped
        let result = try renderer.render(regions: regions, onto: sourceImage)
        #expect(result.size.width == sourceImage.size.width)
    }

    // MARK: - Multiple Regions Tests

    @Test func renderMultipleTranslatedRegions() async throws {
        let renderer = OverlayRenderer()
        let sourceImage = createTestImage(width: 400, height: 200)

        let regions = [
            makeRegion(
                text: "你好",
                translation: "Hello",
                boundingBox: CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.2)
            ),
            makeRegion(
                text: "世界",
                translation: "World",
                boundingBox: CGRect(x: 0.5, y: 0.6, width: 0.3, height: 0.2)
            ),
            makeRegion(
                text: "测试",
                translation: nil,  // No translation - should be skipped
                boundingBox: CGRect(x: 0.3, y: 0.2, width: 0.3, height: 0.2)
            )
        ]

        let result = try renderer.render(regions: regions, onto: sourceImage)

        #expect(result.size.width == sourceImage.size.width)
        #expect(result.size.height == sourceImage.size.height)
    }

    // MARK: - Edge Cases

    @Test func renderWithSmallBoundingBox() async throws {
        let renderer = OverlayRenderer()
        let sourceImage = createTestImage()

        let regions = [
            makeRegion(
                text: "你",
                translation: "Hi",
                boundingBox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
            )
        ]

        let result = try renderer.render(regions: regions, onto: sourceImage)
        #expect(result.size.width == sourceImage.size.width)
    }

    @Test func renderWithLargeBoundingBox() async throws {
        let renderer = OverlayRenderer()
        let sourceImage = createTestImage()

        let regions = [
            makeRegion(
                text: "测试文本",
                translation: "Test Text",
                boundingBox: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
            )
        ]

        let result = try renderer.render(regions: regions, onto: sourceImage)
        #expect(result.size.width == sourceImage.size.width)
    }

    @Test func renderWithLongTranslation() async throws {
        let renderer = OverlayRenderer()
        let sourceImage = createTestImage(width: 200, height: 50)

        let regions = [
            makeRegion(
                text: "短",
                translation: "This is a very long translation text that should be handled gracefully",
                boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
            )
        ]

        // Should not crash with long text
        let result = try renderer.render(regions: regions, onto: sourceImage)
        #expect(result.size.width == sourceImage.size.width)
    }

    // MARK: - Error Handling Tests

    @Test func errorDescriptions() async throws {
        let invalidImageError = OverlayRendererError.invalidImage
        #expect(invalidImageError.errorDescription?.contains("process") == true)

        let renderingError = OverlayRendererError.renderingFailed
        #expect(renderingError.errorDescription?.contains("render") == true)

        let contextError = OverlayRendererError.cgContextCreationFailed
        #expect(contextError.errorDescription?.contains("context") == true)
    }

    // MARK: - Background Color Sampling Tests

    @Test func renderOnDarkBackground() async throws {
        let renderer = OverlayRenderer()
        let sourceImage = createTestImage(color: .black)

        let regions = [
            makeRegion(
                text: "你好",
                translation: "Hello",
                boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
            )
        ]

        // Should render white text on dark background
        let result = try renderer.render(regions: regions, onto: sourceImage)
        #expect(result.size.width == sourceImage.size.width)
    }

    @Test func renderOnLightBackground() async throws {
        let renderer = OverlayRenderer()
        let sourceImage = createTestImage(color: .white)

        let regions = [
            makeRegion(
                text: "你好",
                translation: "Hello",
                boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
            )
        ]

        // Should render black text on light background
        let result = try renderer.render(regions: regions, onto: sourceImage)
        #expect(result.size.width == sourceImage.size.width)
    }

    // MARK: - Private Helper Methods

    /// Compares two CGImages by sampling pixels.
    private func compareImages(_ image1: CGImage, _ image2: CGImage) -> Bool {
        guard image1.width == image2.width,
              image1.height == image2.height else {
            return false
        }

        // Create contexts to get pixel data
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

        // Compare pixel data
        return data1 == data2
    }
}
