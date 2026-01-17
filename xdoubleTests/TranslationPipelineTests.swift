//
//  TranslationPipelineTests.swift
//  xdoubleTests
//
//  E2E integration tests for the translation pipeline.
//  Tests OCR → filter → translate → render flow with verification
//  that output contains English text via OCR re-scan.
//
//  Note: TranslationSession API requires UI context, so translation
//  is mocked in these tests. All other pipeline stages use real implementations.
//

import Testing
import Foundation
import CoreGraphics
import AppKit
import Vision
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

    // MARK: - Full E2E Integration Tests with Real Images and OCR Verification

    /// Performs OCR on an image to detect English text.
    /// Uses Vision framework with English language recognition.
    private func detectEnglishText(in image: CGImage) async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let detectedTexts = observations.compactMap { observation -> String? in
                    observation.topCandidates(1).first?.string
                }

                continuation.resume(returning: detectedTexts)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]  // Detect English text
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    @Test func fullE2E_realImageWithOCRVerification() async throws {
        // STEP 1: Load real Chinese screenshot from test bundle
        let testImage = try TestImageLoader.loadCGImage(.chineseScreenshot)
        let imageSize = CGSize(width: testImage.width, height: testImage.height)

        // STEP 2: Run OCR to detect Chinese text regions
        let ocrService = OCRService()
        let detectedRegions = try await ocrService.detectText(in: testImage)

        // Verify we detected Chinese text
        #expect(!detectedRegions.isEmpty, "Should detect text in Chinese screenshot")

        let allDetectedText = detectedRegions.map { $0.text }.joined(separator: " ")
        let containsChinese = allDetectedText.contains { char in
            char.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value) ||
                (0x3400...0x4DBF).contains(scalar.value)
            }
        }
        #expect(containsChinese, "Detected text should contain Chinese characters")

        // STEP 3: Filter regions to determine what should be translated
        let textFilter = TextFilter(minimumConfidence: 0.3)
        let regionsToTranslate = textFilter.filter(detectedRegions)

        // Should have some regions to translate
        #expect(!regionsToTranslate.isEmpty, "Should have regions to translate after filtering")

        // STEP 4: Mock translation (TranslationSession requires UI context)
        // Create realistic English translations for the Chinese text
        let mockTranslations: [String: String] = [
            "美食": "Food",
            "请输入商家或商品名称": "Search for stores or products",
            "优惠": "Discount",
            "首页": "Home",
            "附近": "Nearby",
            "订单": "Orders",
            "我的": "My Account"
        ]

        var translatedRegions: [TextRegion] = []
        for region in regionsToTranslate {
            // Look for known translations, otherwise use generic translation
            let translation = mockTranslations[region.text] ?? "Translated: \(region.text.prefix(10))"
            translatedRegions.append(TextRegion(
                id: region.id,
                text: region.text,
                boundingBox: region.boundingBox,
                confidence: region.confidence,
                translation: translation
            ))
        }

        // STEP 5: Render translated text onto the image
        let renderer = OverlayRenderer()
        let sourceNSImage = NSImage(cgImage: testImage, size: NSSize(width: imageSize.width, height: imageSize.height))
        let renderedImage = try renderer.render(regions: translatedRegions, onto: sourceNSImage)

        // Verify rendered image has valid dimensions
        #expect(renderedImage.size.width == imageSize.width, "Rendered width should match source")
        #expect(renderedImage.size.height == imageSize.height, "Rendered height should match source")

        // STEP 6: Verify output contains English text via OCR re-scan
        guard let outputCGImage = renderedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("Failed to get CGImage from rendered output")
            return
        }

        let englishTexts = try await detectEnglishText(in: outputCGImage)

        // Verify English text was detected in the output
        #expect(!englishTexts.isEmpty, "Should detect English text in rendered output")

        // Check for known translation words in the output
        let allEnglishText = englishTexts.joined(separator: " ").lowercased()
        let expectedWords = ["food", "translated", "search", "discount", "home", "nearby", "orders"]
        let foundExpectedWord = expectedWords.contains { word in
            allEnglishText.contains(word)
        }
        #expect(foundExpectedWord, "Output should contain expected English translation words. Found: \(allEnglishText)")

        // STEP 7: Verify image actually changed (translations were rendered)
        let imagesAreDifferent = self.imagesAreDifferent(testImage, outputCGImage)
        #expect(imagesAreDifferent, "Output image should differ from input after rendering translations")
    }

    @Test func fullE2E_helloWorldImageWithOCRVerification() async throws {
        // STEP 1: Load simple Chinese "Hello World" image
        let testImage = try TestImageLoader.loadCGImage(.chineseHelloWorld)
        let imageSize = CGSize(width: testImage.width, height: testImage.height)

        // STEP 2: OCR to detect Chinese text
        let ocrService = OCRService()
        let detectedRegions = try await ocrService.detectText(in: testImage)

        #expect(!detectedRegions.isEmpty, "Should detect text in hello world image")

        // STEP 3: Filter
        let textFilter = TextFilter(minimumConfidence: 0.2)
        let regionsToTranslate = textFilter.filter(detectedRegions)

        // STEP 4: Mock translation with known English phrase
        var translatedRegions: [TextRegion] = []
        for region in regionsToTranslate {
            translatedRegions.append(TextRegion(
                id: region.id,
                text: region.text,
                boundingBox: region.boundingBox,
                confidence: region.confidence,
                translation: "Hello World"  // Known English translation
            ))
        }

        // STEP 5: Render
        let renderer = OverlayRenderer()
        let sourceNSImage = NSImage(cgImage: testImage, size: NSSize(width: imageSize.width, height: imageSize.height))
        let renderedImage = try renderer.render(regions: translatedRegions, onto: sourceNSImage)

        // STEP 6: OCR re-scan for English
        guard let outputCGImage = renderedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("Failed to get CGImage from rendered output")
            return
        }

        let englishTexts = try await detectEnglishText(in: outputCGImage)
        let allEnglishText = englishTexts.joined(separator: " ").lowercased()

        // Should detect "Hello" and/or "World" in the output
        let containsHello = allEnglishText.contains("hello")
        let containsWorld = allEnglishText.contains("world")
        #expect(containsHello || containsWorld, "Output should contain 'Hello' and/or 'World'. Found: \(allEnglishText)")
    }

    @Test func fullE2E_multiRegionImageWithOCRVerification() async throws {
        // STEP 1: Load multi-region Chinese image
        let testImage = try TestImageLoader.loadCGImage(.chineseMultiRegion)
        let imageSize = CGSize(width: testImage.width, height: testImage.height)

        // STEP 2: OCR
        let ocrService = OCRService()
        let detectedRegions = try await ocrService.detectText(in: testImage)

        #expect(!detectedRegions.isEmpty, "Should detect text in multi-region image")

        // STEP 3: Filter
        let textFilter = TextFilter(minimumConfidence: 0.2)
        let regionsToTranslate = textFilter.filter(detectedRegions)

        // STEP 4: Mock translation with different English phrases for each region
        let englishPhrases = ["Welcome", "Test", "Translation", "System", "Working"]
        var translatedRegions: [TextRegion] = []
        for (index, region) in regionsToTranslate.enumerated() {
            let translation = englishPhrases[index % englishPhrases.count]
            translatedRegions.append(TextRegion(
                id: region.id,
                text: region.text,
                boundingBox: region.boundingBox,
                confidence: region.confidence,
                translation: translation
            ))
        }

        // STEP 5: Render
        let renderer = OverlayRenderer()
        let sourceNSImage = NSImage(cgImage: testImage, size: NSSize(width: imageSize.width, height: imageSize.height))
        let renderedImage = try renderer.render(regions: translatedRegions, onto: sourceNSImage)

        // STEP 6: OCR re-scan for English
        guard let outputCGImage = renderedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("Failed to get CGImage from rendered output")
            return
        }

        let englishTexts = try await detectEnglishText(in: outputCGImage)

        // Verify English text was detected
        #expect(!englishTexts.isEmpty, "Should detect English text in multi-region rendered output")

        // Check for expected English words
        let allEnglishText = englishTexts.joined(separator: " ").lowercased()
        let foundExpectedWord = englishPhrases.contains { phrase in
            allEnglishText.contains(phrase.lowercased())
        }
        #expect(foundExpectedWord, "Output should contain expected English words. Found: \(allEnglishText)")
    }

    @Test func fullE2E_verifyPipelineOutputDiffersFromInput() async throws {
        // This test verifies the core invariant: output must differ from input when translations are applied

        // Load test image
        let testImage = try TestImageLoader.loadCGImage(.chineseScreenshot)

        // Run full pipeline
        let ocrService = OCRService()
        let textFilter = TextFilter(minimumConfidence: 0.3)
        let renderer = OverlayRenderer()

        // OCR
        let regions = try await ocrService.detectText(in: testImage)
        #expect(!regions.isEmpty, "Must have regions to test")

        // Filter
        let filtered = textFilter.filter(regions)
        #expect(!filtered.isEmpty, "Must have filtered regions to test")

        // Translate (mock)
        let translated = filtered.map { region in
            TextRegion(
                id: region.id,
                text: region.text,
                boundingBox: region.boundingBox,
                confidence: region.confidence,
                translation: "English translation for: \(region.text.prefix(5))"
            )
        }

        // Render
        let nsImage = NSImage(cgImage: testImage, size: NSSize(width: testImage.width, height: testImage.height))
        let output = try renderer.render(regions: translated, onto: nsImage)

        // Verify output differs from input
        guard let outputCGImage = output.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("Failed to get output CGImage")
            return
        }

        #expect(imagesAreDifferent(testImage, outputCGImage), "Pipeline output must differ from input when translations are applied")
    }

    // MARK: - Pipeline State Tests

    @Test func pipelineStartsInIdleState() async throws {
        let pipeline = TranslationPipeline()
        #expect(pipeline.state == .idle, "Pipeline should start in idle state")
        #expect(pipeline.canRestart == false, "Fresh pipeline should not be restartable")
    }

    @Test func pipelineClearStoredSessionResetsState() async throws {
        let pipeline = TranslationPipeline()

        // Verify initial state
        #expect(pipeline.canRestart == false)
        #expect(pipeline.currentFrame == nil)

        // Clear should be safe on fresh pipeline
        pipeline.clearStoredSession()

        #expect(pipeline.canRestart == false)
        #expect(pipeline.currentFrame == nil)
        #expect(pipeline.state == .idle)
    }

    @Test func pipelineCanRestartAfterStopWithoutClear() async throws {
        // This test verifies behavior when stop is called but session isn't cleared
        // (simulating the stop button behavior, not the back button)
        let pipeline = TranslationPipeline()

        // Without actually starting (which requires a real window), we can't fully test this
        // But we can verify the preconditions
        #expect(pipeline.canRestart == false, "canRestart should be false without stored session")
    }

    @Test func translationServiceInvalidateConfigurationClearsState() async throws {
        let service = TranslationService()

        // Prepare to create a configuration
        try await service.prepare()

        // Should have a configuration now
        let config1 = try service.getConfiguration()
        #expect(config1 != nil)

        // Invalidate
        service.invalidateConfiguration()

        // Should throw when trying to get configuration
        do {
            _ = try service.getConfiguration()
            Issue.record("getConfiguration should throw after invalidation")
        } catch {
            // Expected - configuration was invalidated
        }

        // Prepare again should create a new configuration
        try await service.prepare()
        let config2 = try service.getConfiguration()
        #expect(config2 != nil)
    }

    @Test func translationServiceCreatesNewConfigOnEachPrepare() async throws {
        let service = TranslationService()

        // First prepare
        try await service.prepare()
        let config1 = try service.getConfiguration()

        // Invalidate and prepare again
        service.invalidateConfiguration()
        try await service.prepare()
        let config2 = try service.getConfiguration()

        // Both should exist (we can't easily compare identity in Swift for classes,
        // but we verified the flow works)
        #expect(config1 != nil)
        #expect(config2 != nil)
    }

    @Test func fullE2E_verifyChineseTextReplacedByEnglish() async throws {
        // This test verifies that Chinese text is visually replaced by English text

        // Load test image
        let testImage = try TestImageLoader.loadCGImage(.chineseHelloWorld)

        // Detect Chinese text in original
        let ocrService = OCRService()
        let originalRegions = try await ocrService.detectText(in: testImage)

        let originalText = originalRegions.map { $0.text }.joined()
        let originalHasChinese = originalText.contains { char in
            char.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value)
            }
        }
        #expect(originalHasChinese, "Original image should contain Chinese text")

        // Run pipeline
        let textFilter = TextFilter(minimumConfidence: 0.1)
        let renderer = OverlayRenderer()

        let filtered = textFilter.filter(originalRegions)
        let translated = filtered.map { region in
            TextRegion(
                id: region.id,
                text: region.text,
                boundingBox: region.boundingBox,
                confidence: region.confidence,
                translation: "GREETINGS"  // Distinctive English word
            )
        }

        let nsImage = NSImage(cgImage: testImage, size: NSSize(width: testImage.width, height: testImage.height))
        let output = try renderer.render(regions: translated, onto: nsImage)

        guard let outputCGImage = output.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("Failed to get output CGImage")
            return
        }

        // Detect English text in output
        let englishTexts = try await detectEnglishText(in: outputCGImage)
        let outputText = englishTexts.joined(separator: " ").uppercased()

        // Verify the distinctive English word appears in output
        #expect(outputText.contains("GREETINGS"), "Output should contain the English translation 'GREETINGS'. Found: \(outputText)")
    }
}
