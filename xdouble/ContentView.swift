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

    var body: some View {
        Group {
            switch permissionStatus {
            case .unknown:
                checkingPermissionView
            case .denied:
                permissionDeniedView
            case .granted:
                if selectedWindow != nil {
                    translationView
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
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

        // Prepare translation service and create configuration
        Task {
            do {
                try await pipeline.translationService.prepare()
                let config = try pipeline.translationService.getConfiguration()
                // Trigger the translation task by setting the configuration
                translationConfig = config
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                    selectedWindow = nil
                    isStarting = false
                }
            }
        }
    }

    /// Starts the translation pipeline with the provided session.
    private func startTranslation(with session: TranslationSession) async {
        guard let window = selectedWindow else {
            isStarting = false
            return
        }

        do {
            // Start the pipeline - the returned stream is managed internally
            _ = try await pipeline.start(window: window, session: session, fps: 1.5)
            isStarting = false
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showErrorAlert = true
                selectedWindow = nil
                isStarting = false
                translationConfig = nil
            }
        }
    }

    /// Stops the translation pipeline and returns to window selection.
    private func stopTranslation() {
        Task {
            await pipeline.stop()
            selectedWindow = nil
            translationConfig = nil
            isStarting = false
        }
    }
}

#Preview {
    ContentView()
}
