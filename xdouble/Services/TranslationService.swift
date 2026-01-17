//
//  TranslationService.swift
//  xdouble
//
//  Service for translating Chinese text to English using Apple's Translation framework.
//

import Foundation
import Combine
import Translation

/// Status of the translation model download.
enum TranslationModelStatus: Sendable {
    case unknown
    case installed
    case downloadRequired
    case downloading
    case downloadFailed(String)
}

/// Errors that can occur during translation operations.
enum TranslationServiceError: Error, LocalizedError {
    case languageNotSupported
    case languagePairNotAvailable
    case translationFailed(Error)
    case sessionNotAvailable
    case downloadRequired
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .languageNotSupported:
            return "Translation language is not supported on this device."
        case .languagePairNotAvailable:
            return "The Chinese to English language pair is not available. Download may be required."
        case .translationFailed(let error):
            return "Translation failed: \(error.localizedDescription)"
        case .sessionNotAvailable:
            return "Translation session could not be created."
        case .downloadRequired:
            return "The translation model needs to be downloaded. Please allow the download when prompted."
        case .downloadFailed(let reason):
            return "Translation model download failed: \(reason)"
        }
    }
}

/// Service for translating text from Simplified Chinese to English.
/// Uses Apple's on-device Translation framework (macOS 15+).
@MainActor
final class TranslationService: ObservableObject {
    /// The source language (Simplified Chinese)
    let sourceLanguage: Locale.Language

    /// The target language (English)
    let targetLanguage: Locale.Language

    /// The translation session configuration
    private var configuration: TranslationSession.Configuration?

    /// Whether the language pair is available for translation
    private var isAvailable: Bool = false

    /// Current status of the translation model
    @Published private(set) var modelStatus: TranslationModelStatus = .unknown

    /// Creates a TranslationService for Chinese to English translation.
    init() {
        self.sourceLanguage = Locale.Language(identifier: "zh-Hans")
        self.targetLanguage = Locale.Language(identifier: "en")
    }

    /// Checks the current model availability and updates modelStatus.
    /// - Returns: The current model status
    @discardableResult
    func checkModelStatus() async -> TranslationModelStatus {
        let availability = LanguageAvailability()
        let status = await availability.status(from: sourceLanguage, to: targetLanguage)

        switch status {
        case .installed:
            modelStatus = .installed
        case .supported:
            modelStatus = .downloadRequired
        case .unsupported:
            modelStatus = .downloadFailed("Language pair not supported on this device")
        @unknown default:
            modelStatus = .downloadFailed("Unknown availability status")
        }

        return modelStatus
    }

    /// Sets the model status to downloading (call when download begins).
    func setDownloading() {
        modelStatus = .downloading
    }

    /// Sets the model status after download attempt.
    func setDownloadResult(success: Bool, error: String? = nil) {
        if success {
            modelStatus = .installed
        } else {
            modelStatus = .downloadFailed(error ?? "Download failed")
        }
    }

    /// Prepares the translation service by checking language availability.
    /// Call this before translating to ensure the language pair is ready.
    /// - Throws: TranslationServiceError if the language pair is not available
    func prepare() async throws {
        let status = await checkModelStatus()

        switch status {
        case .installed:
            isAvailable = true
            configuration = TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage
            )
        case .downloadRequired:
            // Language is supported but needs download - the .translationTask will handle prompting
            isAvailable = true
            configuration = TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage
            )
        case .downloading:
            // Already in progress, allow configuration for when download completes
            isAvailable = true
            configuration = TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage
            )
        case .downloadFailed(let reason):
            throw TranslationServiceError.downloadFailed(reason)
        case .unknown:
            throw TranslationServiceError.languageNotSupported
        }
    }

    /// Gets the current translation configuration.
    /// - Returns: The configuration if available
    /// - Throws: TranslationServiceError if not prepared
    func getConfiguration() throws -> TranslationSession.Configuration {
        guard let config = configuration else {
            throw TranslationServiceError.sessionNotAvailable
        }
        return config
    }

    /// Checks if the language pair needs to be downloaded.
    /// - Returns: true if download is needed
    func needsDownload() async -> Bool {
        let availability = LanguageAvailability()
        let status = await availability.status(from: sourceLanguage, to: targetLanguage)
        return status == .supported
    }

    /// Translates a single text string from Chinese to English.
    /// - Parameter text: The Chinese text to translate
    /// - Parameter session: The translation session to use
    /// - Returns: The translated English text
    /// - Throws: TranslationServiceError if translation fails
    func translate(_ text: String, using session: TranslationSession) async throws -> String {
        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            throw TranslationServiceError.translationFailed(error)
        }
    }

    /// Translates multiple text strings from Chinese to English in a batch.
    /// - Parameter texts: Array of Chinese text strings to translate
    /// - Parameter session: The translation session to use
    /// - Returns: Array of translated English text strings (same order as input)
    /// - Throws: TranslationServiceError if translation fails
    func translate(_ texts: [String], using session: TranslationSession) async throws -> [String] {
        guard !texts.isEmpty else { return [] }

        do {
            let requests = texts.map { TranslationSession.Request(sourceText: $0) }
            let responses = try await session.translations(from: requests)
            return responses.map { $0.targetText }
        } catch {
            throw TranslationServiceError.translationFailed(error)
        }
    }

    /// Translates text regions and returns updated regions with translations.
    /// - Parameter regions: Array of TextRegion to translate
    /// - Parameter session: The translation session to use
    /// - Returns: Array of TextRegion with translation property filled in
    /// - Throws: TranslationServiceError if translation fails
    func translate(regions: [TextRegion], using session: TranslationSession) async throws -> [TextRegion] {
        guard !regions.isEmpty else { return [] }

        let texts = regions.map { $0.text }
        let translations = try await translate(texts, using: session)

        return zip(regions, translations).map { region, translation in
            var updatedRegion = region
            updatedRegion.translation = translation
            return updatedRegion
        }
    }
}

/// A simple translation cache to avoid re-translating the same text.
actor TranslationCache {
    private var cache: [String: String] = [:]
    private let maxSize: Int

    init(maxSize: Int = 1000) {
        self.maxSize = maxSize
    }

    /// Gets a cached translation if available.
    func get(_ key: String) -> String? {
        cache[key]
    }

    /// Stores a translation in the cache.
    func set(_ key: String, value: String) {
        // Simple LRU-ish behavior: clear when too large
        if cache.count >= maxSize {
            cache.removeAll()
        }
        cache[key] = value
    }

    /// Clears all cached translations.
    func clear() {
        cache.removeAll()
    }
}
