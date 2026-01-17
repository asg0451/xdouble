//
//  TextFilter.swift
//  xdouble
//
//  Service for filtering text regions to determine which should be translated.
//

import Foundation

/// Service for filtering text regions to skip translation of certain content.
/// Filters out numbers, single characters, low-confidence OCR results, and English text.
struct TextFilter: Sendable {

    /// Minimum OCR confidence threshold for translation (0.0-1.0)
    let minimumConfidence: Float

    /// Creates a new TextFilter with the specified confidence threshold.
    /// - Parameter minimumConfidence: Minimum OCR confidence required for translation (default: 0.5)
    init(minimumConfidence: Float = 0.5) {
        self.minimumConfidence = minimumConfidence
    }

    /// Determines whether a text region should be translated.
    /// Returns false for:
    /// - Empty or whitespace-only text
    /// - Numbers-only text (e.g., "123", "45.67")
    /// - Single characters
    /// - Low confidence OCR results (below minimumConfidence)
    /// - Text that is already primarily English
    ///
    /// - Parameter region: The text region to evaluate
    /// - Returns: true if the region should be translated, false otherwise
    func shouldTranslate(_ region: TextRegion) -> Bool {
        let text = region.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter empty or whitespace-only text
        if text.isEmpty {
            return false
        }

        // Filter single characters
        if text.count == 1 {
            return false
        }

        // Filter low confidence results
        if region.confidence < minimumConfidence {
            return false
        }

        // Filter numbers-only text (including decimal numbers and numbers with separators)
        if isNumbersOnly(text) {
            return false
        }

        // Filter text that is primarily English/Latin characters
        if isPrimarilyEnglish(text) {
            return false
        }

        return true
    }

    /// Filters an array of text regions, returning only those that should be translated.
    /// - Parameter regions: Array of text regions to filter
    /// - Returns: Array of text regions that should be translated
    func filter(_ regions: [TextRegion]) -> [TextRegion] {
        regions.filter { shouldTranslate($0) }
    }

    // MARK: - Private Methods

    /// Checks if the text consists only of numbers and common number formatting characters.
    /// - Parameter text: The text to check
    /// - Returns: true if the text is numbers-only
    private func isNumbersOnly(_ text: String) -> Bool {
        // Allow digits, decimal points, commas, spaces, plus/minus signs, percent
        let allowedCharacterSet = CharacterSet(charactersIn: "0123456789.,+-% ")
        let textCharacterSet = CharacterSet(charactersIn: text)

        // Check if all characters are in the allowed set
        guard textCharacterSet.isSubset(of: allowedCharacterSet) else {
            return false
        }

        // Must contain at least one digit
        return text.contains(where: { $0.isNumber })
    }

    /// Checks if the text is primarily composed of English/Latin characters.
    /// Text is considered "primarily English" if more than 70% of its
    /// alphabetic characters are in the basic Latin range.
    /// - Parameter text: The text to check
    /// - Returns: true if the text is primarily English/Latin
    private func isPrimarilyEnglish(_ text: String) -> Bool {
        var latinCount = 0
        var nonLatinCount = 0

        for scalar in text.unicodeScalars {
            // Skip non-letter characters (numbers, punctuation, whitespace)
            guard CharacterSet.letters.contains(scalar) else {
                continue
            }

            // Basic Latin (A-Z, a-z) and Latin Extended-A/B
            // Basic Latin: U+0041-U+005A (A-Z), U+0061-U+007A (a-z)
            // Latin Extended-A: U+0100-U+017F
            // Latin Extended-B: U+0180-U+024F
            let value = scalar.value
            if (value >= 0x0041 && value <= 0x005A) ||  // A-Z
               (value >= 0x0061 && value <= 0x007A) ||  // a-z
               (value >= 0x0100 && value <= 0x024F) {   // Latin Extended
                latinCount += 1
            } else {
                nonLatinCount += 1
            }
        }

        // If no alphabetic characters, it's not "primarily English"
        let totalLetters = latinCount + nonLatinCount
        guard totalLetters > 0 else {
            return false
        }

        // More than 70% Latin characters means primarily English
        let latinRatio = Double(latinCount) / Double(totalLetters)
        return latinRatio > 0.7
    }
}
