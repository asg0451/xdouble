//
//  OCRService.swift
//  xdouble
//
//  Service for detecting Chinese text in images using the Vision framework.
//

import Foundation
import Vision
import CoreGraphics
import CoreImage

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
final class OCRService: Sendable {
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
        // Preprocess and upscale for better OCR accuracy
        let processedImage = preprocessImage(image)
        let upscaledImage = upscaleImage(processedImage)

        // Primary pass on processed image
        let primaryRegions = try await performOCR(on: upscaledImage)

        // Secondary pass on inverted image (for dark mode / white-on-dark text)
        var secondaryRegions: [TextRegion] = []
        if let invertedImage = invertImage(upscaledImage) {
            secondaryRegions = (try? await performOCR(on: invertedImage)) ?? []
        }

        // Merge results, avoiding duplicates
        return mergeRegions(primary: primaryRegions, secondary: secondaryRegions)
    }

    /// Perform OCR on a single image
    private func performOCR(on image: CGImage) async throws -> [TextRegion] {
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
                    // Get top 3 candidates and pick best by confidence, then length as tiebreaker
                    let candidates = observation.topCandidates(3)
                    guard let bestCandidate = candidates.max(by: { c1, c2 in
                        if c1.confidence != c2.confidence {
                            return c1.confidence < c2.confidence
                        }
                        return c1.string.count < c2.string.count
                    }) else { return nil }

                    // Filter by confidence if threshold is set
                    if bestCandidate.confidence < self.minimumConfidence {
                        return nil
                    }

                    return TextRegion(
                        text: bestCandidate.string,
                        boundingBox: observation.boundingBox,
                        confidence: bestCandidate.confidence
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

    // MARK: - Image Processing Helpers

    /// Apply light contrast boost and sharpening to improve OCR accuracy
    private func preprocessImage(_ image: CGImage) -> CGImage {
        let ciImage = CIImage(cgImage: image)
        let context = CIContext()

        // Light contrast boost
        guard let contrastFilter = CIFilter(name: "CIColorControls") else { return image }
        contrastFilter.setValue(ciImage, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.08, forKey: kCIInputContrastKey)
        contrastFilter.setValue(1.0, forKey: kCIInputSaturationKey)
        guard let contrastOutput = contrastFilter.outputImage else { return image }

        // Light sharpening
        guard let sharpenFilter = CIFilter(name: "CISharpenLuminance") else { return image }
        sharpenFilter.setValue(contrastOutput, forKey: kCIInputImageKey)
        sharpenFilter.setValue(0.4, forKey: kCIInputSharpnessKey)
        guard let output = sharpenFilter.outputImage,
              let result = context.createCGImage(output, from: output.extent) else { return image }

        return result
    }

    /// Upscale image to improve detection of small Chinese glyphs
    private func upscaleImage(_ image: CGImage, scale: CGFloat = 2.0) -> CGImage {
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let output = filter.outputImage else { return image }
        return CIContext().createCGImage(output, from: output.extent) ?? image
    }

    /// Invert image colors for dark mode detection
    private func invertImage(_ image: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorInvert") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    /// Merge regions from primary and secondary passes, avoiding duplicates
    private func mergeRegions(primary: [TextRegion], secondary: [TextRegion]) -> [TextRegion] {
        var merged = primary
        for region in secondary {
            let hasOverlap = primary.contains { p in
                let overlap = p.boundingBox.intersection(region.boundingBox)
                return overlap.width * overlap.height > region.boundingBox.width * region.boundingBox.height * 0.5
            }
            if !hasOverlap { merged.append(region) }
        }
        return merged
    }
}
