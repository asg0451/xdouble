//
//  TestAssetTests.swift
//  xdoubleTests
//
//  Tests to verify bundled test assets are present and functional.
//

import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import xdouble

struct TestAssetTests {

    // MARK: - Test Image Loading Tests

    @Test func allTestImagesExistInBundle() async throws {
        let allExist = TestImageLoader.verifyTestImagesExist()
        #expect(allExist, "All expected test images should exist in the bundle")
    }

    @Test func canLoadChineseHelloWorldImage() async throws {
        let cgImage = try TestImageLoader.loadCGImage(.chineseHelloWorld)

        #expect(cgImage.width > 0, "Image should have valid width")
        #expect(cgImage.height > 0, "Image should have valid height")
        #expect(cgImage.width == 400, "chinese_hello_world.png should be 400px wide")
        #expect(cgImage.height == 200, "chinese_hello_world.png should be 200px tall")
    }

    @Test func canLoadChineseMultiRegionImage() async throws {
        let cgImage = try TestImageLoader.loadCGImage(.chineseMultiRegion)

        #expect(cgImage.width > 0, "Image should have valid width")
        #expect(cgImage.height > 0, "Image should have valid height")
        #expect(cgImage.width == 600, "chinese_multi_region.png should be 600px wide")
        #expect(cgImage.height == 400, "chinese_multi_region.png should be 400px tall")
    }

    @Test func canLoadImageAsNSImage() async throws {
        let nsImage = try TestImageLoader.loadNSImage(.chineseHelloWorld)

        #expect(nsImage.size.width > 0, "NSImage should have valid width")
        #expect(nsImage.size.height > 0, "NSImage should have valid height")
    }

    @Test func allTestImageURLsAreValid() async throws {
        let urls = TestImageLoader.allTestImageURLs()

        // Should have at least 2 test images
        #expect(urls.count >= 2, "Should have at least 2 test images")

        // All URLs should point to existing files
        for url in urls {
            #expect(FileManager.default.fileExists(atPath: url.path), "Image file should exist: \(url.lastPathComponent)")
        }
    }

    // MARK: - OCR Integration with Bundled Images

    @Test func ocrDetectsTextInBundledHelloWorldImage() async throws {
        let cgImage = try TestImageLoader.loadCGImage(.chineseHelloWorld)
        let ocrService = OCRService()

        let regions = try await ocrService.detectText(in: cgImage)

        // Should detect at least one text region
        #expect(!regions.isEmpty, "OCR should detect text in chinese_hello_world.png")

        // Detected text should contain Chinese characters
        let allText = regions.map { $0.text }.joined()
        let containsChinese = allText.contains { char in
            char.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value) ||
                (0x3400...0x4DBF).contains(scalar.value)
            }
        }
        #expect(containsChinese, "Detected text should contain Chinese characters. Got: \(allText)")
    }

    @Test func ocrDetectsMultipleRegionsInMultiRegionImage() async throws {
        let cgImage = try TestImageLoader.loadCGImage(.chineseMultiRegion)
        let ocrService = OCRService()

        let regions = try await ocrService.detectText(in: cgImage)

        // Multi-region image has 5 text regions, should detect at least some
        #expect(!regions.isEmpty, "OCR should detect text in chinese_multi_region.png")

        // Log detected regions for debugging
        for region in regions {
            // Verify each region has valid bounds
            #expect(region.boundingBox.width > 0)
            #expect(region.boundingBox.height > 0)
            #expect(region.confidence >= 0 && region.confidence <= 1)
        }
    }

    @Test func bundledImagesProduceBoundingBoxes() async throws {
        let cgImage = try TestImageLoader.loadCGImage(.chineseHelloWorld)
        let ocrService = OCRService()

        let regions = try await ocrService.detectText(in: cgImage)

        for region in regions {
            // Bounding boxes should be in normalized coordinates (0.0-1.0)
            #expect(region.boundingBox.origin.x >= 0)
            #expect(region.boundingBox.origin.y >= 0)
            #expect(region.boundingBox.maxX <= 1)
            #expect(region.boundingBox.maxY <= 1)
        }
    }

    // MARK: - Pipeline Integration with Bundled Images

    @Test func bundledImageWorksWithFullPipeline() async throws {
        // Load test image
        let testImage = try TestImageLoader.loadCGImage(.chineseHelloWorld)
        let nsImage = try TestImageLoader.loadNSImage(.chineseHelloWorld)

        // OCR
        let ocrService = OCRService()
        let detectedRegions = try await ocrService.detectText(in: testImage)
        #expect(!detectedRegions.isEmpty, "Should detect text")

        // Filter
        let textFilter = TextFilter(minimumConfidence: 0.3)
        let filteredRegions = textFilter.filter(detectedRegions)

        // Mock translation (since TranslationSession requires UI)
        let translatedRegions = filteredRegions.map { region in
            TextRegion(
                id: region.id,
                text: region.text,
                boundingBox: region.boundingBox,
                confidence: region.confidence,
                translation: "Hello World"
            )
        }

        // Render
        let renderer = OverlayRenderer()
        let outputImage = try renderer.render(regions: translatedRegions, onto: nsImage)

        // Verify output
        #expect(outputImage.size.width == nsImage.size.width)
        #expect(outputImage.size.height == nsImage.size.height)
    }

    // MARK: - Error Handling Tests

    @Test func loadingNonexistentImageThrowsError() async throws {
        do {
            _ = try TestImageLoader.loadCGImage(named: "nonexistent_image")
            Issue.record("Should have thrown an error for nonexistent image")
        } catch TestImageLoader.LoadError.imageNotFound {
            // Expected error
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
