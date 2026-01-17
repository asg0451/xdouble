//
//  ContentView.swift
//  xdouble
//
//  Main view that orchestrates window selection and translation display.
//

import SwiftUI
import Translation

/// Represents the current screen recording permission status.
enum PermissionStatus {
    case unknown
    case granted
    case denied
}

/// Represents the state of translation setup.
enum TranslationSetupState {
    case notStarted
    case checkingModel
    case downloadRequired
    case downloading
    case ready
    case failed(String)
}

/// The main content view that switches between window selection and translation display.
struct ContentView: View {
    /// The translation pipeline manages the capture → OCR → translate → render flow
    @StateObject private var pipeline = TranslationPipeline()

    /// The currently selected window to translate
    @State private var selectedWindow: CaptureWindow?

    /// Translation session configuration for triggering the translation task
    @State private var translationConfig: TranslationSession.Configuration?

    /// Whether we're in the process of starting translation
    @State private var isStarting = false

    /// Error message to display
    @State private var errorMessage: String?

    /// Whether to show the error alert
    @State private var showErrorAlert = false

    /// Screen recording permission status
    @State private var permissionStatus: PermissionStatus = .unknown

    /// Translation model setup state
    @State private var translationSetupState: TranslationSetupState = .notStarted

    var body: some View {
        Group {
            switch permissionStatus {
            case .unknown:
                checkingPermissionView
            case .denied:
                permissionDeniedView
            case .granted:
                if selectedWindow != nil {
                    // Show translation setup UI when needed
                    switch translationSetupState {
                    case .checkingModel, .downloadRequired, .downloading:
                        translationSetupView
                    case .failed(let message):
                        translationSetupFailedView(message: message)
                    default:
                        translationView
                    }
                } else {
                    windowPickerView
                }
            }
        }
        .translationTask(translationConfig) { session in
            await startTranslation(with: session)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {
                errorMessage = nil
            }
            if errorMessage?.contains("permission") == true || errorMessage?.contains("Permission") == true {
                Button("Open System Settings") {
                    openScreenRecordingSettings()
                }
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .task {
            await checkPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check permission when app becomes active (user may have granted it in System Settings)
            Task {
                await checkPermission()
            }
        }
    }

    // MARK: - Subviews

    /// View shown while checking permission status
    private var checkingPermissionView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Checking permissions...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("checkingPermissionView")
    }

    /// View shown when screen recording permission is denied
    private var permissionDeniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Screen Recording Permission Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("permissionRequiredTitle")

                Text("xdouble needs screen recording permission to capture and translate window content.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            VStack(spacing: 12) {
                Button(action: openScreenRecordingSettings) {
                    Label("Open System Settings", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("openSystemSettingsButton")

                Text("After enabling permission, return to this app.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button("Check Again") {
                Task {
                    await checkPermission()
                }
            }
            .buttonStyle(.link)
            .accessibilityIdentifier("checkAgainButton")
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("permissionDeniedView")
    }

    /// View shown during translation model setup (checking, downloading)
    private var translationSetupView: some View {
        VStack(spacing: 24) {
            switch translationSetupState {
            case .checkingModel:
                ProgressView()
                    .scaleEffect(1.5)
                VStack(spacing: 8) {
                    Text("Checking Translation Model...")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Verifying that the Chinese to English translation model is available.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

            case .downloadRequired:
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                VStack(spacing: 8) {
                    Text("Translation Model Download Required")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("downloadRequiredTitle")
                    Text("The Chinese to English translation model needs to be downloaded. A system prompt will appear to start the download.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                Text("Please wait...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

            case .downloading:
                ProgressView()
                    .scaleEffect(1.5)
                VStack(spacing: 8) {
                    Text("Downloading Translation Model...")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("downloadingTitle")
                    Text("The translation model is being downloaded. This only needs to happen once.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

            default:
                EmptyView()
            }

            Button("Cancel") {
                cancelSetup()
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("translationSetupView")
    }

    /// View shown when translation setup fails
    private func translationSetupFailedView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Translation Setup Failed")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("setupFailedTitle")

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            HStack(spacing: 12) {
                Button("Try Again") {
                    retrySetup()
                }
                .buttonStyle(.borderedProminent)

                Button("Choose Different Window") {
                    cancelSetup()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("translationSetupFailedView")
    }

    /// Window picker view for selecting a source window
    private var windowPickerView: some View {
        WindowPickerView(
            captureService: pipeline.captureService,
            onSelect: { window in
                selectWindow(window)
            }
        )
    }

    /// Translation view showing the translated frames
    private var translationView: some View {
        TranslatedWindowView(
            pipeline: pipeline,
            onStop: {
                stopTranslation()
            },
            onPlay: {
                retrySetup()
            }
        )
    }

    // MARK: - Actions

    /// Checks the current screen recording permission status.
    private func checkPermission() async {
        // First check if we already have permission
        if CaptureService.hasScreenRecordingPermission() {
            // Try to actually enumerate windows to confirm permission works
            do {
                try await pipeline.captureService.refreshWindows()
                permissionStatus = .granted
            } catch {
                // If refresh fails with permission error, permission is denied
                if let captureError = error as? CaptureError, captureError == .permissionDenied {
                    permissionStatus = .denied
                } else if error.localizedDescription.lowercased().contains("permission") {
                    permissionStatus = .denied
                } else {
                    // Some other error, but permission is likely granted
                    permissionStatus = .granted
                }
            }
        } else {
            // Request permission - this will show system dialog first time
            let granted = CaptureService.requestScreenRecordingPermission()
            if granted {
                permissionStatus = .granted
            } else {
                permissionStatus = .denied
            }
        }
    }

    /// Opens System Settings to the Screen Recording privacy pane.
    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Selects a window and prepares for translation.
    private func selectWindow(_ window: CaptureWindow) {
        guard !isStarting else { return }

        selectedWindow = window
        isStarting = true
        translationSetupState = .checkingModel

        // Prepare translation service and create configuration
        Task {
            do {
                // First check if model is available
                let modelStatus = await pipeline.translationService.checkModelStatus()

                switch modelStatus {
                case .downloadRequired:
                    translationSetupState = .downloadRequired
                    // Set to downloading since the .translationTask will trigger the download UI
                    pipeline.translationService.setDownloading()
                    translationSetupState = .downloading
                case .downloadFailed(let reason):
                    translationSetupState = .failed(reason)
                    isStarting = false
                    return
                case .installed:
                    // Model is ready, transition to ready state immediately
                    translationSetupState = .ready
                case .downloading, .unknown:
                    // Continue with setup, let .translationTask handle it
                    break
                }

                try await pipeline.translationService.prepare()
                let config = try pipeline.translationService.getConfiguration()

                // Trigger the translation task by setting the configuration
                // This may show a system download prompt if needed
                translationConfig = config
            } catch {
                await MainActor.run {
                    let errorDesc = error.localizedDescription
                    translationSetupState = .failed(errorDesc)
                    isStarting = false
                }
            }
        }
    }

    /// Cancels the translation setup and returns to window selection.
    private func cancelSetup() {
        selectedWindow = nil
        translationSetupState = .notStarted
        translationConfig = nil
        isStarting = false
    }

    /// Retries the translation setup with the current window.
    private func retrySetup() {
        guard selectedWindow != nil else {
            cancelSetup()
            return
        }

        // If the pipeline can restart (has stored session), use that directly
        if pipeline.canRestart {
            Task {
                do {
                    _ = try await pipeline.restart()
                } catch {
                    translationSetupState = .failed(error.localizedDescription)
                }
            }
            return
        }

        // No stored session - go through full setup
        translationConfig = nil
        translationSetupState = .notStarted
        isStarting = false
        selectWindow(selectedWindow!)
    }

    /// Starts the translation pipeline with the provided session.
    private func startTranslation(with session: TranslationSession) async {
        guard let window = selectedWindow else {
            isStarting = false
            translationSetupState = .notStarted
            return
        }

        do {
            // Model download succeeded if we got here - update the service status
            pipeline.translationService.setDownloadResult(success: true)

            // Start the pipeline - the returned stream is managed internally
            _ = try await pipeline.start(window: window, session: session, fps: 1.5)
            translationSetupState = .ready
            isStarting = false
        } catch {
            await MainActor.run {
                let errorDesc = error.localizedDescription
                translationSetupState = .failed(errorDesc)
                pipeline.translationService.setDownloadResult(success: false, error: errorDesc)
                isStarting = false
                translationConfig = nil
            }
        }
    }

    /// Stops the translation pipeline (stays on translation view with play button).
    private func stopTranslation() {
        Task {
            await pipeline.stop()
            // Don't clear selectedWindow - stay on translation view showing idle state with play button
            // translationSession is kept so we can restart quickly
            isStarting = false
        }
    }

    /// Returns to window selection (clears everything).
    private func returnToWindowPicker() {
        Task {
            await pipeline.stop()
            selectedWindow = nil
            translationConfig = nil
            translationSetupState = .notStarted
            isStarting = false
        }
    }
}

#Preview {
    ContentView()
}
