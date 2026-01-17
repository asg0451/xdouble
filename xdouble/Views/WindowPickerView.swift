//
//  WindowPickerView.swift
//  xdouble
//
//  SwiftUI view for selecting a window to translate.
//

import SwiftUI
import ScreenCaptureKit

/// A view that displays available windows and allows the user to select one for translation.
struct WindowPickerView: View {
    /// The capture service for window enumeration
    @ObservedObject var captureService: CaptureService

    /// Callback when a window is selected
    let onSelect: (CaptureWindow) -> Void

    /// Loading state for window enumeration
    @State private var isLoading = false

    /// Error message to display
    @State private var errorMessage: String?

    /// Thumbnails cache
    @State private var thumbnails: [CGWindowID: NSImage] = [:]

    /// Whether we're loading thumbnails
    @State private var loadingThumbnails = false

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 16) {
            headerView

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(message: error)
            } else if captureService.availableWindows.isEmpty {
                emptyStateView
            } else {
                windowGridView
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .task {
            await loadWindows()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Select a Window")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Choose a window to translate")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: {
                Task {
                    await loadWindows()
                }
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading windows...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Unable to Load Windows")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if message.contains("permission") {
                Button("Open System Settings") {
                    openScreenRecordingSettings()
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Try Again") {
                Task {
                    await loadWindows()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "macwindow")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Windows Available")
                .font(.headline)

            Text("Open an application window to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Refresh") {
                Task {
                    await loadWindows()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var windowGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(captureService.availableWindows) { window in
                    WindowCard(
                        window: window,
                        thumbnail: thumbnails[window.id],
                        onSelect: {
                            onSelect(window)
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Actions

    private func loadWindows() async {
        isLoading = true
        errorMessage = nil

        do {
            try await captureService.refreshWindows()
            await loadThumbnails()
        } catch let error as CaptureError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadThumbnails() async {
        loadingThumbnails = true
        var newThumbnails: [CGWindowID: NSImage] = [:]

        for window in captureService.availableWindows {
            do {
                let frame = try await captureService.captureFrame(from: window)
                let nsImage = NSImage(cgImage: frame.image, size: NSSize(width: frame.image.width, height: frame.image.height))
                newThumbnails[window.id] = nsImage
            } catch {
                // Use placeholder for failed captures
            }
        }

        thumbnails = newThumbnails
        loadingThumbnails = false
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A card view displaying a single window option.
struct WindowCard: View {
    let window: CaptureWindow
    let thumbnail: NSImage?
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                thumbnailView
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(window.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(window.applicationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail = thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                Color(nsColor: .separatorColor).opacity(0.3)
                Image(systemName: "macwindow")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    WindowPickerView(
        captureService: CaptureService(),
        onSelect: { window in
            print("Selected: \(window.title)")
        }
    )
}
