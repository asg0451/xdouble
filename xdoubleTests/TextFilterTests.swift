//
//  TextFilterTests.swift
//  xdoubleTests
//
//  Tests for TextFilter smart text filtering.
//

import Testing
import Foundation
import CoreGraphics
@testable import xdouble

struct TextFilterTests {

    // MARK: - Helper Methods

    /// Creates a TextRegion with default values for testing.
    private func makeRegion(
        text: String,
        confidence: Float = 0.9
    ) -> TextRegion {
        TextRegion(
            text: text,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1),
            confidence: confidence
        )
    }

    // MARK: - Basic Functionality Tests

    @Test func defaultConfidenceThreshold() async throws {
        let filter = TextFilter()
        #expect(filter.minimumConfidence == 0.5)
    }

    @Test func customConfidenceThreshold() async throws {
        let filter = TextFilter(minimumConfidence: 0.7)
        #expect(filter.minimumConfidence == 0.7)
    }

    // MARK: - Empty/Whitespace Text Tests

    @Test func filterEmptyText() async throws {
        let filter = TextFilter()
        let region = makeRegion(text: "")
        #expect(filter.shouldTranslate(region) == false)
    }

    @Test func filterWhitespaceOnlyText() async throws {
        let filter = TextFilter()

        let spaces = makeRegion(text: "   ")
        #expect(filter.shouldTranslate(spaces) == false)

        let newlines = makeRegion(text: "\n\n")
        #expect(filter.shouldTranslate(newlines) == false)

        let tabs = makeRegion(text: "\t\t")
        #expect(filter.shouldTranslate(tabs) == false)
    }

    // MARK: - Single Character Tests

    @Test func filterSingleCharacter() async throws {
        let filter = TextFilter()

        let singleChinese = makeRegion(text: "中")
        #expect(filter.shouldTranslate(singleChinese) == false)

        let singleEnglish = makeRegion(text: "A")
        #expect(filter.shouldTranslate(singleEnglish) == false)

        let singleNumber = makeRegion(text: "5")
        #expect(filter.shouldTranslate(singleNumber) == false)
    }

    @Test func allowMultipleCharacters() async throws {
        let filter = TextFilter()

        let twoChars = makeRegion(text: "你好")
        #expect(filter.shouldTranslate(twoChars) == true)

        let threeChars = makeRegion(text: "中文字")
        #expect(filter.shouldTranslate(threeChars) == true)
    }

    // MARK: - Low Confidence Tests

    @Test func filterLowConfidence() async throws {
        let filter = TextFilter()

        let lowConfidence = makeRegion(text: "你好世界", confidence: 0.3)
        #expect(filter.shouldTranslate(lowConfidence) == false)

        let borderlineConfidence = makeRegion(text: "你好世界", confidence: 0.49)
        #expect(filter.shouldTranslate(borderlineConfidence) == false)
    }

    @Test func allowHighConfidence() async throws {
        let filter = TextFilter()

        let atThreshold = makeRegion(text: "你好世界", confidence: 0.5)
        #expect(filter.shouldTranslate(atThreshold) == true)

        let aboveThreshold = makeRegion(text: "你好世界", confidence: 0.9)
        #expect(filter.shouldTranslate(aboveThreshold) == true)
    }

    @Test func customConfidenceFiltering() async throws {
        let filter = TextFilter(minimumConfidence: 0.7)

        let belowCustom = makeRegion(text: "你好世界", confidence: 0.6)
        #expect(filter.shouldTranslate(belowCustom) == false)

        let aboveCustom = makeRegion(text: "你好世界", confidence: 0.8)
        #expect(filter.shouldTranslate(aboveCustom) == true)
    }

    // MARK: - Numbers-Only Tests

    @Test func filterPureNumbers() async throws {
        let filter = TextFilter()

        let integers = makeRegion(text: "12345")
        #expect(filter.shouldTranslate(integers) == false)

        let decimal = makeRegion(text: "123.45")
        #expect(filter.shouldTranslate(decimal) == false)

        let percentage = makeRegion(text: "45%")
        #expect(filter.shouldTranslate(percentage) == false)

        let negative = makeRegion(text: "-100")
        #expect(filter.shouldTranslate(negative) == false)

        let formatted = makeRegion(text: "1,234,567")
        #expect(filter.shouldTranslate(formatted) == false)

        let withSpaces = makeRegion(text: "12 345")
        #expect(filter.shouldTranslate(withSpaces) == false)
    }

    @Test func allowMixedNumbersAndText() async throws {
        let filter = TextFilter()

        let chineseWithNumbers = makeRegion(text: "第123章")
        #expect(filter.shouldTranslate(chineseWithNumbers) == true)

        let numbersWithChinese = makeRegion(text: "100个")
        #expect(filter.shouldTranslate(numbersWithChinese) == true)
    }

    // MARK: - English Text Tests

    @Test func filterEnglishText() async throws {
        let filter = TextFilter()

        let pureEnglish = makeRegion(text: "Hello World")
        #expect(filter.shouldTranslate(pureEnglish) == false)

        let englishSentence = makeRegion(text: "This is a test")
        #expect(filter.shouldTranslate(englishSentence) == false)

        let englishWithPunctuation = makeRegion(text: "Hello, World!")
        #expect(filter.shouldTranslate(englishWithPunctuation) == false)
    }

    @Test func allowChineseText() async throws {
        let filter = TextFilter()

        let pureChinese = makeRegion(text: "你好世界")
        #expect(filter.shouldTranslate(pureChinese) == true)

        let chineseSentence = makeRegion(text: "这是一个测试")
        #expect(filter.shouldTranslate(chineseSentence) == true)
    }

    @Test func allowMixedChineseEnglishWithMoreChinese() async throws {
        let filter = TextFilter()

        // More Chinese than English should pass
        let mostlyChinese = makeRegion(text: "这是中文ABC")
        #expect(filter.shouldTranslate(mostlyChinese) == true)
    }

    @Test func filterMixedTextWithMostlyEnglish() async throws {
        let filter = TextFilter()

        // More English than Chinese should be filtered
        let mostlyEnglish = makeRegion(text: "Hello World 中")
        #expect(filter.shouldTranslate(mostlyEnglish) == false)
    }

    // MARK: - Filter Method Tests

    @Test func filterArrayOfRegions() async throws {
        let filter = TextFilter()

        let regions = [
            makeRegion(text: "你好"),           // Should pass - Chinese
            makeRegion(text: ""),               // Should fail - empty
            makeRegion(text: "A"),              // Should fail - single char
            makeRegion(text: "12345"),          // Should fail - numbers only
            makeRegion(text: "Hello"),          // Should fail - English
            makeRegion(text: "测试", confidence: 0.3),  // Should fail - low confidence
            makeRegion(text: "中文测试"),        // Should pass - Chinese
        ]

        let filtered = filter.filter(regions)

        #expect(filtered.count == 2)
        #expect(filtered[0].text == "你好")
        #expect(filtered[1].text == "中文测试")
    }

    @Test func filterEmptyArray() async throws {
        let filter = TextFilter()
        let filtered = filter.filter([])
        #expect(filtered.isEmpty)
    }

    // MARK: - Edge Cases

    @Test func handleUnicodeEmoji() async throws {
        let filter = TextFilter()

        // Emojis with Chinese should still translate
        let chineseWithEmoji = makeRegion(text: "你好😀")
        #expect(filter.shouldTranslate(chineseWithEmoji) == true)
    }

    @Test func handleChinesePunctuation() async throws {
        let filter = TextFilter()

        // Chinese with Chinese punctuation
        let withPunctuation = makeRegion(text: "你好！世界？")
        #expect(filter.shouldTranslate(withPunctuation) == true)
    }

    @Test func handleLeadingTrailingWhitespace() async throws {
        let filter = TextFilter()

        // Whitespace should be trimmed before evaluation
        let withSpaces = makeRegion(text: "  你好世界  ")
        #expect(filter.shouldTranslate(withSpaces) == true)
    }
}
