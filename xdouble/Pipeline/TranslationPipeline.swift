//
//  TranslationPipeline.swift
//  xdouble
//
//  Coordinates the capture → OCR → filter → translate → render pipeline.
//

import Foundation
import AppKit
import Combine
import Translation

/// State of the translation pipeline.
enum PipelineState: Sendable {
    case idle
    case starting
    case running
    case stopping
    case error(String)
}

/// Errors that can occur during pipeline operation.
enum PipelineError: Error, LocalizedError {
    case alreadyRunning
    case notRunning
    case captureError(Error)
    case ocrError(Error)
    case translationError(Error)
    case renderingError(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Pipeline is already running."
        case .notRunning:
            return "Pipeline is not running."
        case .captureError(let error):
            return "Capture failed: \(error.localizedDescription)"
        case .ocrError(let error):
            return "OCR failed: \(error.localizedDescription)"
        case .translationError(let error):
            return "Translation failed: \(error.localizedDescription)"
        case .renderingError(let error):
            return "Rendering failed: \(error.localizedDescription)"
        case .cancelled:
            return "Pipeline was cancelled."
        }
    }
}

/// Actor that orchestrates the full translation pipeline.
/// Coordinates capture → OCR → filter → translate → render flow.
@MainActor
final class TranslationPipeline: ObservableObject {

    // MARK: - Published State

    /// Current state of the pipeline
    @Published private(set) var state: PipelineState = .idle

    /// The most recent translated frame
    @Published private(set) var currentFrame: TranslatedFrame?

    /// Statistics about pipeline performance
    @Published private(set) var frameCount: Int = 0

    /// Average processing time per frame
    @Published private(set) var averageProcessingTime: TimeInterval = 0

    /// Whether a frame is currently being processed
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Services

    /// Service for capturing window frames
    let captureService: CaptureService

    /// Service for OCR text detection
    private let ocrService: OCRService

    /// Filter for determining which text to translate
    private let textFilter: TextFilter

    /// Service for translation (configuration only, session managed separately)
    let translationService: TranslationService

    /// Renderer for overlaying translated text
    private let overlayRenderer: OverlayRenderer

    /// Cache for translations to avoid redundant work
    private let translationCache: TranslationCache

    // MARK: - Pipeline State

    /// Task running the pipeline loop
    private var pipelineTask: Task<Void, Never>?

    /// Continuation for publishing frames to external consumers
    private var frameContinuation: AsyncStream<TranslatedFrame>.Continuation?

    /// Accumulated processing times for averaging
    private var processingTimes: [TimeInterval] = []

    // MARK: - Initialization

    /// Creates a new TranslationPipeline with default services.
    init() {
        self.captureService = CaptureService()
        self.ocrService = OCRService(minimumConfidence: 0.0)
        self.textFilter = TextFilter(minimumConfidence: 0.5)
        self.translationService = TranslationService()
        self.overlayRenderer = OverlayRenderer()
        self.translationCache = TranslationCache()
    }

    /// Creates a new TranslationPipeline with custom services.
    /// - Parameters:
    ///   - captureService: Service for capturing window frames
    ///   - ocrService: Service for OCR text detection
    ///   - textFilter: Filter for determining which text to translate
    ///   - translationService: Service for translation
    ///   - overlayRenderer: Renderer for overlaying translated text
    init(
        captureService: CaptureService,
        ocrService: OCRService,
        textFilter: TextFilter,
        translationService: TranslationService,
        overlayRenderer: OverlayRenderer
    ) {
        self.captureService = captureService
        self.ocrService = ocrService
        self.textFilter = textFilter
        self.translationService = translationService
        self.overlayRenderer = overlayRenderer
        self.translationCache = TranslationCache()
    }

    // MARK: - Public Methods

    /// Starts the translation pipeline for the specified window.
    /// - Parameters:
    ///   - window: The window to capture and translate
    ///   - session: The TranslationSession to use for translation
    ///   - fps: Frames per second (defaults to 1.0)
    /// - Returns: AsyncStream of TranslatedFrame for external consumers
    func start(window: CaptureWindow, session: TranslationSession, fps: Double = 1.0) async throws -> AsyncStream<TranslatedFrame> {
        guard case .idle = state else {
            throw PipelineError.alreadyRunning
        }

        state = .starting
        frameCount = 0
        processingTimes = []
        averageProcessingTime = 0

        // Prepare translation service
        try await translationService.prepare()

        // Start capture stream
        let captureStream: AsyncStream<CapturedFrame>
        do {
            captureStream = try await captureService.startCapture(window: window, fps: fps)
        } catch {
            state = .error(error.localizedDescription)
            throw PipelineError.captureError(error)
        }

        // Create output stream for translated frames
        let outputStream = AsyncStream<TranslatedFrame> { continuation in
            self.frameContinuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.stopSync()
                }
            }
        }

        // Start the pipeline processing task
        state = .running
        pipelineTask = Task { @MainActor in
            await self.runPipelineLoop(captureStream: captureStream, session: session)
        }

        return outputStream
    }

    /// Stops the translation pipeline.
    func stop() async {
        guard case .running = state else { return }

        state = .stopping
        pipelineTask?.cancel()
        pipelineTask = nil

        await captureService.stopCapture()
        frameContinuation?.finish()
        frameContinuation = nil

        isProcessing = false
        state = .idle
    }

    /// Processes a single frame through the pipeline.
    /// Useful for testing or single-frame processing.
    /// - Parameters:
    ///   - frame: The captured frame to process
    ///   - session: The TranslationSession to use
    /// - Returns: The translated frame
    func processFrame(_ frame: CapturedFrame, session: TranslationSession) async throws -> TranslatedFrame {
        let startTime = Date()

        // Step 1: OCR - detect text regions
        let allRegions: [TextRegion]
        do {
            allRegions = try await ocrService.detectText(in: frame)
        } catch {
            throw PipelineError.ocrError(error)
        }

        // Step 2: Filter - determine which regions to translate
        let regionsToTranslate = textFilter.filter(allRegions)

        // Step 3: Translate - with caching
        let translatedRegions: [TextRegion]
        do {
            translatedRegions = try await translateWithCache(regions: regionsToTranslate, session: session)
        } catch {
            throw PipelineError.translationError(error)
        }

        // Step 4: Render - overlay translated text
        let renderedImage: NSImage
        do {
            // Convert CGImage to NSImage for rendering
            let sourceImage = NSImage(cgImage: frame.image, size: NSSize(width: frame.image.width, height: frame.image.height))
            renderedImage = try overlayRenderer.render(regions: translatedRegions, onto: sourceImage)
        } catch {
            throw PipelineError.renderingError(error)
        }

        let processingDuration = Date().timeIntervalSince(startTime)

        return TranslatedFrame(
            image: renderedImage,
            size: CGSize(width: frame.image.width, height: frame.image.height),
            regions: translatedRegions,
            captureTime: frame.captureTime,
            processingDuration: processingDuration
        )
    }

    // MARK: - Private Methods

    /// Synchronous cleanup helper.
    private func stopSync() {
        pipelineTask?.cancel()
        pipelineTask = nil
        frameContinuation?.finish()
        frameContinuation = nil
        isProcessing = false
        state = .idle
    }

    /// Main pipeline loop that processes frames.
    private func runPipelineLoop(captureStream: AsyncStream<CapturedFrame>, session: TranslationSession) async {
        for await frame in captureStream {
            // Check for cancellation
            if Task.isCancelled {
                break
            }

            // Mark as processing
            isProcessing = true

            do {
                let translatedFrame = try await processFrame(frame, session: session)

                // Update published state
                currentFrame = translatedFrame
                frameCount += 1
                updateAverageProcessingTime(translatedFrame.processingDuration)

                // Publish to external consumers
                frameContinuation?.yield(translatedFrame)
            } catch {
                // Log error but continue processing
                // In a production app, we might want to emit error frames or use a different strategy
                print("Pipeline error processing frame: \(error)")
            }

            // Mark processing complete
            isProcessing = false
        }

        // Loop ended - either stream finished or cancelled
        isProcessing = false
        if case .running = state {
            state = .idle
        }
    }

    /// Translates regions with caching to avoid redundant translations.
    private func translateWithCache(regions: [TextRegion], session: TranslationSession) async throws -> [TextRegion] {
        guard !regions.isEmpty else { return [] }

        var result: [TextRegion] = []
        var uncachedRegions: [TextRegion] = []
        var uncachedIndices: [Int] = []

        // Check cache for existing translations
        for (index, region) in regions.enumerated() {
            if let cached = await translationCache.get(region.text) {
                var cachedRegion = region
                cachedRegion.translation = cached
                result.append(cachedRegion)
            } else {
                uncachedRegions.append(region)
                uncachedIndices.append(index)
                result.append(region) // Placeholder, will be updated
            }
        }

        // Translate uncached regions
        if !uncachedRegions.isEmpty {
            let translatedRegions = try await translationService.translate(regions: uncachedRegions, using: session)

            // Update results and cache
            for (i, translatedRegion) in translatedRegions.enumerated() {
                let originalIndex = uncachedIndices[i]
                result[originalIndex] = translatedRegion

                // Cache the translation
                if let translation = translatedRegion.translation {
                    await translationCache.set(translatedRegion.text, value: translation)
                }
            }
        }

        return result
    }

    /// Updates the running average of processing times.
    private func updateAverageProcessingTime(_ duration: TimeInterval) {
        processingTimes.append(duration)

        // Keep last 30 samples for rolling average
        if processingTimes.count > 30 {
            processingTimes.removeFirst()
        }

        let total = processingTimes.reduce(0, +)
        averageProcessingTime = total / Double(processingTimes.count)
    }
}
