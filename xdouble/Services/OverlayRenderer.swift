//
//  OverlayRenderer.swift
//  xdouble
//
//  Service for rendering translated text overlays onto captured frames.
//

import Foundation
import AppKit
import CoreGraphics

/// Errors that can occur during overlay rendering.
enum OverlayRendererError: Error, LocalizedError {
    case invalidImage
    case renderingFailed
    case cgContextCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Failed to process the input image."
        case .renderingFailed:
            return "Failed to render the overlay."
        case .cgContextCreationFailed:
            return "Failed to create graphics context."
        }
    }
}

/// Service for rendering translated text overlays onto images.
/// Uses CoreGraphics for compositing translated text on top of the original frame.
/// Marked nonisolated to allow use from any actor context.
nonisolated final class OverlayRenderer: Sendable {

    /// Padding ratio around text within the bounding box
    let paddingRatio: CGFloat

    /// Creates an OverlayRenderer with the specified configuration.
    /// - Parameter paddingRatio: Padding as a fraction of the bounding box (default: 0.1)
    init(paddingRatio: CGFloat = 0.1) {
        self.paddingRatio = paddingRatio
    }

    /// Renders translated text regions onto an image.
    /// - Parameters:
    ///   - regions: Array of TextRegion with translations to render
    ///   - image: The source image to overlay text onto
    /// - Returns: NSImage with translated text overlaid on the original
    /// - Throws: OverlayRendererError if rendering fails
    func render(regions: [TextRegion], onto image: NSImage) throws -> NSImage {
        // Get the image size
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OverlayRendererError.invalidImage
        }

        let width = cgImage.width
        let height = cgImage.height
        let size = CGSize(width: width, height: height)

        // Create a bitmap context to draw into
        guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw OverlayRendererError.cgContextCreationFailed
        }

        // Draw the original image
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))

        // Filter regions that have translations
        let translatedRegions = regions.filter { $0.translation != nil }

        // Render each translated region
        for region in translatedRegions {
            guard let translation = region.translation, !translation.isEmpty else {
                continue
            }

            // Convert normalized bounding box to absolute coordinates
            // Note: CoreGraphics origin is bottom-left, same as Vision
            let absoluteBox = absoluteBoundingBoxCG(for: region.boundingBox, imageSize: size)

            // Sample background color from the region
            let backgroundColor = sampleBackgroundColor(
                from: cgImage,
                in: absoluteBox,
                imageSize: size
            )

            // Draw background rectangle
            drawBackground(
                in: context,
                rect: absoluteBox,
                color: backgroundColor
            )

            // Calculate font size based on box height
            let fontSize = calculateFontSize(for: absoluteBox, text: translation)

            // Draw the translated text
            drawText(
                translation,
                in: context,
                rect: absoluteBox,
                fontSize: fontSize,
                backgroundColor: backgroundColor
            )
        }

        // Create the final image from the context
        guard let outputCGImage = context.makeImage() else {
            throw OverlayRendererError.renderingFailed
        }

        return NSImage(cgImage: outputCGImage, size: NSSize(width: width, height: height))
    }

    // MARK: - Private Methods

    /// Converts normalized bounding box to absolute coordinates for CoreGraphics.
    /// CoreGraphics origin is bottom-left, same as Vision framework.
    private func absoluteBoundingBoxCG(for boundingBox: CGRect, imageSize: CGSize) -> CGRect {
        let x = boundingBox.origin.x * imageSize.width
        let y = boundingBox.origin.y * imageSize.height
        let width = boundingBox.width * imageSize.width
        let height = boundingBox.height * imageSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Samples the dominant background color from a region of the image.
    private func sampleBackgroundColor(from image: CGImage, in rect: CGRect, imageSize: CGSize) -> NSColor {
        // Clamp rect to image bounds
        let clampedRect = rect.intersection(CGRect(origin: .zero, size: imageSize))
        guard !clampedRect.isEmpty,
              clampedRect.width > 0,
              clampedRect.height > 0 else {
            return NSColor.white
        }

        // Sample from edges of the bounding box to get background color
        // This avoids sampling the text itself
        let samplePoints = [
            CGPoint(x: clampedRect.minX + 2, y: clampedRect.midY),  // Left edge
            CGPoint(x: clampedRect.maxX - 2, y: clampedRect.midY),  // Right edge
            CGPoint(x: clampedRect.midX, y: clampedRect.minY + 2),  // Bottom edge
            CGPoint(x: clampedRect.midX, y: clampedRect.maxY - 2)   // Top edge
        ]

        var totalRed: CGFloat = 0
        var totalGreen: CGFloat = 0
        var totalBlue: CGFloat = 0
        var sampleCount = 0

        // Create a small context for sampling pixels
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            return NSColor.white
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard let data = context.data else {
            return NSColor.white
        }

        let bytesPerPixel = 4
        let bytesPerRow = context.bytesPerRow

        for point in samplePoints {
            let x = Int(point.x)
            let y = Int(point.y)

            // Bounds check
            guard x >= 0, x < image.width, y >= 0, y < image.height else {
                continue
            }

            let offset = y * bytesPerRow + x * bytesPerPixel
            let pixelData = data.advanced(by: offset).assumingMemoryBound(to: UInt8.self)

            totalRed += CGFloat(pixelData[0]) / 255.0
            totalGreen += CGFloat(pixelData[1]) / 255.0
            totalBlue += CGFloat(pixelData[2]) / 255.0
            sampleCount += 1
        }

        guard sampleCount > 0 else {
            return NSColor.white
        }

        let avgRed = totalRed / CGFloat(sampleCount)
        let avgGreen = totalGreen / CGFloat(sampleCount)
        let avgBlue = totalBlue / CGFloat(sampleCount)

        return NSColor(red: avgRed, green: avgGreen, blue: avgBlue, alpha: 1.0)
    }

    /// Draws a background rectangle to cover the original text.
    private func drawBackground(in context: CGContext, rect: CGRect, color: NSColor) {
        // Expand rect slightly for better coverage
        let expandedRect = rect.insetBy(dx: -2, dy: -2)

        context.saveGState()
        context.setFillColor(color.cgColor)
        context.fill(expandedRect)
        context.restoreGState()
    }

    /// Calculates an appropriate font size for the translated text to fit within the bounding box.
    private func calculateFontSize(for rect: CGRect, text: String) -> CGFloat {
        // Start with a font size based on the box height
        let baseSize = rect.height * 0.8

        // Account for text length - reduce size for longer text
        let targetWidth = rect.width * (1.0 - 2 * paddingRatio)

        // Use a simple heuristic: assume average character width is roughly 0.6x height for English
        let estimatedTextWidth = CGFloat(text.count) * baseSize * 0.6

        if estimatedTextWidth > targetWidth && text.count > 0 {
            // Scale down to fit width
            let scaleFactor = targetWidth / estimatedTextWidth
            return max(baseSize * scaleFactor, 8.0)  // Minimum 8pt
        }

        return max(baseSize, 8.0)
    }

    /// Draws translated text centered within the bounding box.
    private func drawText(
        _ text: String,
        in context: CGContext,
        rect: CGRect,
        fontSize: CGFloat,
        backgroundColor: NSColor
    ) {
        // Determine text color based on background luminance
        let textColor = contrastingColor(for: backgroundColor)

        // Create attributed string with styling
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)

        // Calculate text size
        let textSize = attributedString.size()

        // Center the text within the bounding box
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )

        // Draw using NSGraphicsContext since AttributedString drawing requires it
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        attributedString.draw(in: textRect)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Returns a contrasting color (black or white) for the given background color.
    private func contrastingColor(for backgroundColor: NSColor) -> NSColor {
        // Convert to RGB color space if needed
        guard let rgbColor = backgroundColor.usingColorSpace(.deviceRGB) else {
            return NSColor.black
        }

        // Calculate relative luminance using sRGB coefficients
        let luminance = 0.299 * rgbColor.redComponent +
                        0.587 * rgbColor.greenComponent +
                        0.114 * rgbColor.blueComponent

        // Use white text on dark backgrounds, black text on light backgrounds
        return luminance > 0.5 ? NSColor.black : NSColor.white
    }
}
