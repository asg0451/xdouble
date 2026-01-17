//
//  TranslatedFrame.swift
//  xdouble
//
//  Data model representing a processed frame with translated text overlaid.
//

import Foundation
import AppKit

/// Represents a processed frame with translated text rendered on top of the original image.
struct TranslatedFrame: Identifiable, Sendable {
    /// Unique identifier for this frame
    let id: UUID

    /// The rendered image with translated text overlaid
    let image: NSImage

    /// The dimensions of the frame
    let size: CGSize

    /// All text regions detected in this frame (with translations)
    let regions: [TextRegion]

    /// Timestamp when the original frame was captured
    let captureTime: Date

    /// Duration of the processing pipeline (OCR + translation + rendering)
    let processingDuration: TimeInterval

    /// Number of regions that were successfully translated
    var translatedRegionCount: Int {
        regions.filter { $0.translation != nil }.count
    }

    /// Creates a new TranslatedFrame with the given properties.
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - image: The rendered image with translations
    ///   - size: Dimensions of the frame
    ///   - regions: Text regions detected and translated
    ///   - captureTime: When the original frame was captured
    ///   - processingDuration: How long processing took
    init(
        id: UUID = UUID(),
        image: NSImage,
        size: CGSize,
        regions: [TextRegion],
        captureTime: Date,
        processingDuration: TimeInterval
    ) {
        self.id = id
        self.image = image
        self.size = size
        self.regions = regions
        self.captureTime = captureTime
        self.processingDuration = processingDuration
    }
}

/// Statistics about a TranslatedFrame for debugging and display
extension TranslatedFrame {
    /// Human-readable description of processing performance
    var performanceDescription: String {
        let ms = processingDuration * 1000
        return String(format: "%.0fms, %d regions", ms, regions.count)
    }

    /// Effective frames per second based on processing duration
    var effectiveFPS: Double {
        guard processingDuration > 0 else { return 0 }
        return 1.0 / processingDuration
    }
}
