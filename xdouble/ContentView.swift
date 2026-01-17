//
//  ContentView.swift
//  xdouble
//
//  Main view that orchestrates window selection and translation display.
//

import SwiftUI
import Translation

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

    var body: some View {
        Group {
            if selectedWindow != nil {
                translationView
            } else {
                windowPickerView
            }
        }
        .translationTask(translationConfig) { session in
            await startTranslation(with: session)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Subviews

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
