//
//  TestImageLoader.swift
//  xdoubleTests
//
//  Helper for loading test images from the test bundle.
//

import Foundation
import AppKit
import CoreGraphics

/// Helper for loading test images from the test bundle
enum TestImageLoader {

    /// Available test images in the bundle
    enum TestImage: String, CaseIterable {
        /// Simple "Hello World" image with Chinese text (你好世界)
        case chineseHelloWorld = "chinese_hello_world"

        /// Multi-region image with multiple Chinese phrases
        case chineseMultiRegion = "chinese_multi_region"

        /// Real screenshot from a Chinese food delivery app
        /// Contains: 美食, 请输入商家或商品名称, restaurant names, ratings, etc.
        case chineseScreenshot = "chinese_screenshot"
    }

    /// Error types for image loading
    enum LoadError: Error, LocalizedError {
        case imageNotFound(String)
        case failedToLoadImage(String)
        case failedToConvertToCGImage(String)

        var errorDescription: String? {
            switch self {
            case .imageNotFound(let name):
                return "Test image not found in bundle: \(name)"
            case .failedToLoadImage(let name):
                return "Failed to load test image: \(name)"
            case .failedToConvertToCGImage(let name):
                return "Failed to convert test image to CGImage: \(name)"
            }
        }
    }

    /// Loads a test image as NSImage from the test bundle
    /// - Parameter image: The test image to load
    /// - Returns: The loaded NSImage
    /// - Throws: LoadError if the image cannot be found or loaded
    static func loadNSImage(_ image: TestImage) throws -> NSImage {
        let bundle = Bundle(for: BundleToken.self)

        guard let url = bundle.url(forResource: image.rawValue, withExtension: "png") else {
            throw LoadError.imageNotFound(image.rawValue)
        }

        guard let nsImage = NSImage(contentsOf: url) else {
            throw LoadError.failedToLoadImage(image.rawValue)
        }

        return nsImage
    }

    /// Loads a test image as CGImage from the test bundle
    /// - Parameter image: The test image to load
    /// - Returns: The loaded CGImage
    /// - Throws: LoadError if the image cannot be found or loaded
    static func loadCGImage(_ image: TestImage) throws -> CGImage {
        let nsImage = try loadNSImage(image)

        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw LoadError.failedToConvertToCGImage(image.rawValue)
        }

        return cgImage
    }

    /// Loads a test image by name (without extension) from the test bundle
    /// - Parameter name: The image file name without extension
    /// - Returns: The loaded CGImage
    /// - Throws: LoadError if the image cannot be found or loaded
    static func loadCGImage(named name: String) throws -> CGImage {
        let bundle = Bundle(for: BundleToken.self)

        guard let url = bundle.url(forResource: name, withExtension: "png") else {
            throw LoadError.imageNotFound(name)
        }

        guard let nsImage = NSImage(contentsOf: url) else {
            throw LoadError.failedToLoadImage(name)
        }

        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw LoadError.failedToConvertToCGImage(name)
        }

        return cgImage
    }

    /// Returns all available test image URLs
    static func allTestImageURLs() -> [URL] {
        let bundle = Bundle(for: BundleToken.self)
        return TestImage.allCases.compactMap { image in
            bundle.url(forResource: image.rawValue, withExtension: "png")
        }
    }

    /// Checks if all expected test images are present in the bundle
    static func verifyTestImagesExist() -> Bool {
        let bundle = Bundle(for: BundleToken.self)
        return TestImage.allCases.allSatisfy { image in
            bundle.url(forResource: image.rawValue, withExtension: "png") != nil
        }
    }
}

/// Token class for accessing the test bundle
private class BundleToken {}
