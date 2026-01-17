//
//  TextRegion.swift
//  xdouble
//
//  Data model representing a detected text region from OCR.
//

import Foundation
import CoreGraphics

/// Represents a region of detected text with its location and optional translation.
struct TextRegion: Identifiable, Sendable {
    /// Unique identifier for this region
    let id: UUID

    /// The original detected text (Chinese)
    let text: String

    /// The bounding box of the text in normalized coordinates (0.0-1.0).
    /// Origin is at bottom-left, matching Vision framework conventions.
    let boundingBox: CGRect

    /// OCR confidence score (0.0-1.0)
    let confidence: Float

    /// The translated text (English), nil if not yet translated
    var translation: String?

    /// Creates a new TextRegion with the given properties.
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - text: The detected text content
    ///   - boundingBox: Normalized bounding box (0.0-1.0 coordinates)
    ///   - confidence: OCR confidence score (0.0-1.0)
    ///   - translation: Optional translated text
    init(
        id: UUID = UUID(),
        text: String,
        boundingBox: CGRect,
        confidence: Float,
        translation: String? = nil
    ) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.translation = translation
    }

    /// Returns the bounding box converted to absolute coordinates for a given image size.
    /// Flips Y-axis from Vision coordinates (origin bottom-left) to AppKit/CoreGraphics
    /// coordinates (origin top-left for images).
    /// - Parameter imageSize: The size of the image in pixels
    /// - Returns: CGRect in absolute pixel coordinates with origin at top-left
    func absoluteBoundingBox(for imageSize: CGSize) -> CGRect {
        let x = boundingBox.origin.x * imageSize.width
        let width = boundingBox.width * imageSize.width
        let height = boundingBox.height * imageSize.height
        // Flip Y coordinate: Vision origin is bottom-left, we want top-left
        let y = (1.0 - boundingBox.origin.y - boundingBox.height) * imageSize.height

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

extension TextRegion: Equatable {
    static func == (lhs: TextRegion, rhs: TextRegion) -> Bool {
        lhs.id == rhs.id
    }
}

extension TextRegion: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
