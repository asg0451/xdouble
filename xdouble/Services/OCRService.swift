//
//  OCRService.swift
//  xdouble
//
//  Service for detecting Chinese text in images using the Vision framework.
//

import Foundation
import Vision
import CoreGraphics

/// Errors that can occur during OCR operations.
enum OCRError: Error, LocalizedError {
    case imageCreationFailed
    case requestFailed(Error)
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .imageCreationFailed:
            return "Failed to create image for text recognition."
        case .requestFailed(let error):
            return "Text recognition failed: \(error.localizedDescription)"
        case .noTextFound:
            return "No text was detected in the image."
        }
    }
}

/// Service for detecting text in images using Vision framework.
/// Optimized for Simplified Chinese text recognition.
/// Marked nonisolated to allow use from any actor context.
nonisolated final class OCRService: Sendable {
    /// Minimum confidence threshold for including detected text
    let minimumConfidence: Float

    /// Recognition languages to use (defaults to Simplified Chinese)
    let recognitionLanguages: [String]

    /// Creates an OCRService with the specified configuration.
    /// - Parameters:
    ///   - minimumConfidence: Minimum confidence threshold (0.0-1.0, defaults to 0.0)
    ///   - recognitionLanguages: Languages to recognize (defaults to Simplified Chinese)
    nonisolated init(minimumConfidence: Float = 0.0, recognitionLanguages: [String] = ["zh-Hans"]) {
        self.minimumConfidence = minimumConfidence
        self.recognitionLanguages = recognitionLanguages
    }

    /// Detect text regions in a CGImage.
    /// - Parameter image: The image to analyze
    /// - Returns: Array of TextRegion with detected text and bounding boxes
    /// - Throws: OCRError if recognition fails
    func detectText(in image: CGImage) async throws -> [TextRegion] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.requestFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let regions = observations.compactMap { observation -> TextRegion? in
                    // Get the top candidate for this observation
                    guard let candidate = observation.topCandidates(1).first else {
                        return nil
                    }

                    // Filter by confidence if threshold is set
                    if candidate.confidence < self.minimumConfidence {
                        return nil
                    }

                    return TextRegion(
                        text: candidate.string,
                        boundingBox: observation.boundingBox,
                        confidence: candidate.confidence
                    )
                }

                continuation.resume(returning: regions)
            }

            // Configure the request for Chinese text recognition
            request.recognitionLevel = .accurate
            request.recognitionLanguages = recognitionLanguages
            request.usesLanguageCorrection = true

            // Create and perform the request
            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.requestFailed(error))
            }
        }
    }

    /// Detect text regions in a CapturedFrame.
    /// - Parameter frame: The captured frame to analyze
    /// - Returns: Array of TextRegion with detected text and bounding boxes
    /// - Throws: OCRError if recognition fails
    func detectText(in frame: CapturedFrame) async throws -> [TextRegion] {
        try await detectText(in: frame.image)
    }

    /// Get the supported recognition languages available on this system.
    /// - Parameter recognitionLevel: The recognition level to check (defaults to .accurate)
    /// - Returns: Array of language identifiers
    nonisolated static func supportedLanguages(for recognitionLevel: VNRequestTextRecognitionLevel = .accurate) -> [String] {
        // Create a request to query supported languages (macOS 13+ API)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        do {
            return try request.supportedRecognitionLanguages()
        } catch {
            // Fallback to default languages
            return ["zh-Hans", "en-US"]
        }
    }
}
