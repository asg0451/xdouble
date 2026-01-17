//
//  CaptureService.swift
//  xdouble
//
//  Service for capturing frames from selected windows using ScreenCaptureKit.
//

import Foundation
import ScreenCaptureKit
import AppKit
import Combine

/// Represents an available window that can be captured.
/// This struct contains only Sendable data; the actual SCWindow reference
/// is stored separately in CaptureService and looked up by windowID when needed.
struct CaptureWindow: Identifiable, Sendable, Hashable {
    let id: CGWindowID
    let title: String
    let applicationName: String
    let frame: CGRect

    init(scWindow: SCWindow) {
        self.id = scWindow.windowID
        self.title = scWindow.title ?? "Untitled"
        self.applicationName = scWindow.owningApplication?.applicationName ?? "Unknown"
        self.frame = scWindow.frame
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CaptureWindow, rhs: CaptureWindow) -> Bool {
        lhs.id == rhs.id
    }
}

/// A captured frame from a window.
struct CapturedFrame: Sendable {
    let image: CGImage
    let contentRect: CGRect
    let captureTime: Date

    var size: CGSize {
        CGSize(width: image.width, height: image.height)
    }
}

/// Errors that can occur during capture operations.
enum CaptureError: Error, LocalizedError {
    case permissionDenied
    case noWindowsAvailable
    case windowNotFound
    case streamCreationFailed
    case frameCaptureFailed
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission is required. Please grant permission in System Settings > Privacy & Security > Screen Recording."
        case .noWindowsAvailable:
            return "No windows available for capture."
        case .windowNotFound:
            return "The selected window is no longer available."
        case .streamCreationFailed:
            return "Failed to create capture stream."
        case .frameCaptureFailed:
            return "Failed to capture frame from window."
        case .invalidConfiguration:
            return "Invalid capture configuration."
        }
    }
}

/// Service for enumerating windows and capturing frames.
@MainActor
final class CaptureService: NSObject, ObservableObject {
    /// Current stream configuration
    private(set) var framesPerSecond: Double = 1.0

    /// Published list of available windows
    @Published private(set) var availableWindows: [CaptureWindow] = []

    /// Whether a capture stream is active
    @Published private(set) var isCapturing: Bool = false

    /// The currently selected window for capture
    @Published private(set) var selectedWindow: CaptureWindow?

    /// Active stream for capturing frames
    private var stream: SCStream?

    /// Stream output delegate
    private var streamOutput: CaptureStreamOutput?

    /// Continuation for async frame delivery
    /// Note: Using nonisolated(unsafe) because AsyncStream.Continuation is thread-safe
    nonisolated(unsafe) private var frameContinuation: AsyncStream<CapturedFrame>.Continuation?

    /// Storage for SCWindow references, keyed by windowID.
    /// SCWindow is not Sendable, so we keep it separate from CaptureWindow
    /// and only access it on the MainActor within this service.
    private var scWindowsByID: [CGWindowID: SCWindow] = [:]

    /// Check if screen recording permission is granted.
    /// - Returns: true if permission is granted, false otherwise
    static func hasScreenRecordingPermission() -> Bool {
        // CGPreflightScreenCaptureAccess returns true if we have permission
        // or if we're in a state where we can request it
        return CGPreflightScreenCaptureAccess()
    }

    /// Request screen recording permission from the user.
    /// - Returns: true if permission was granted
    static func requestScreenRecordingPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }

    /// Refresh the list of available windows.
    /// - Throws: CaptureError if permission denied or no windows available
    func refreshWindows() async throws {
        if !Self.hasScreenRecordingPermission() {
            // Try requesting permission
            if !Self.requestScreenRecordingPermission() {
                throw CaptureError.permissionDenied
            }
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // Filter to windows that are visible and have a reasonable size
        let windows = content.windows.filter { window in
            window.frame.width >= 50 && window.frame.height >= 50 &&
            window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
        }

        // Update the SCWindow lookup dictionary
        scWindowsByID.removeAll()
        for scWindow in windows {
            scWindowsByID[scWindow.windowID] = scWindow
        }

        availableWindows = windows.map { CaptureWindow(scWindow: $0) }

        if availableWindows.isEmpty {
            throw CaptureError.noWindowsAvailable
        }
    }

    /// Get a window by its ID.
    /// - Parameter windowID: The window ID to look up
    /// - Returns: The CaptureWindow if found
    func window(withID windowID: CGWindowID) -> CaptureWindow? {
        availableWindows.first { $0.id == windowID }
    }

    /// Start capturing frames from the specified window.
    /// - Parameters:
    ///   - window: The window to capture
    ///   - fps: Frames per second (1-2 recommended, defaults to 1)
    /// - Returns: An AsyncStream of captured frames
    func startCapture(window: CaptureWindow, fps: Double = 1.0) async throws -> AsyncStream<CapturedFrame> {
        // Look up the SCWindow from our storage
        guard let scWindow = scWindowsByID[window.id] else {
            throw CaptureError.windowNotFound
        }

        if isCapturing {
            await stopCapture()
            // Wait briefly for cleanup
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        framesPerSecond = max(0.1, min(fps, 30.0)) // Clamp to reasonable range
        selectedWindow = window

        // Create stream configuration
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2 // Retina scale
        config.height = Int(window.frame.height) * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        // Create content filter for the specific window
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)

        // Create the stream
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        self.stream = stream

        // Create async stream for frame delivery
        let frameStream = AsyncStream<CapturedFrame> { continuation in
            self.frameContinuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.stopCaptureSync()
                }
            }
        }

        // Create and add stream output
        let output = CaptureStreamOutput { [weak self] frame in
            self?.frameContinuation?.yield(frame)
        }
        self.streamOutput = output

        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))

        // Start the stream
        try await stream.startCapture()
        isCapturing = true

        return frameStream
    }

    /// Stop the current capture stream.
    func stopCapture() async {
        guard isCapturing, let stream = stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            // Stream may already be stopped
        }

        stopCaptureSync()
    }

    /// Synchronous cleanup for stream resources.
    private func stopCaptureSync() {
        stream = nil
        streamOutput = nil
        frameContinuation?.finish()
        frameContinuation = nil
        isCapturing = false
        selectedWindow = nil
    }

    /// Capture a single frame from the specified window.
    /// - Parameter window: The window to capture
    /// - Returns: A captured frame
    func captureFrame(from window: CaptureWindow) async throws -> CapturedFrame {
        // Look up the SCWindow from our storage
        guard let scWindow = scWindowsByID[window.id] else {
            throw CaptureError.windowNotFound
        }

        guard Self.hasScreenRecordingPermission() else {
            throw CaptureError.permissionDenied
        }

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2
        config.height = Int(window.frame.height) * 2
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return CapturedFrame(
            image: image,
            contentRect: window.frame,
            captureTime: Date()
        )
    }
}

/// Stream output handler that converts sample buffers to CapturedFrame.
private final class CaptureStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onFrame: @Sendable (CapturedFrame) -> Void
    /// Reused CIContext for efficient image conversion across frames
    private let ciContext = CIContext()

    init(onFrame: @escaping @Sendable (CapturedFrame) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        guard let imageBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)

        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        // Get content rect from attachments if available
        // ScreenCaptureKit stores contentRect as a dictionary representation of CGRect
        var contentRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let attachment = attachments.first,
           let rectValue = attachment[.contentRect] {
            // NSDictionary is toll-free bridged with CFDictionary
            if let rectDict = rectValue as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: rectDict) {
                contentRect = rect
            }
        }

        let frame = CapturedFrame(
            image: cgImage,
            contentRect: contentRect,
            captureTime: Date()
        )

        onFrame(frame)
    }
}
