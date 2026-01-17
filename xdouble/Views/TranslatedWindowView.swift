//
//  TranslatedWindowView.swift
//  xdouble
//
//  Displays translated frames from the TranslationPipeline with performance stats overlay.
//

import SwiftUI

/// A view that displays the translated frames from the TranslationPipeline.
struct TranslatedWindowView: View {
    /// The translation pipeline providing frames
    @ObservedObject var pipeline: TranslationPipeline

    /// Callback when stop button is pressed
    let onStop: () -> Void

    /// Callback when play button is pressed (to restart translation)
    let onPlay: () -> Void

    /// Callback when back button is pressed (to return to window picker)
    let onBack: () -> Void

    /// Whether to show the stats overlay
    @State private var showStats = true

    /// Local font size multiplier (synced to pipeline)
    @State private var fontSizeMultiplier: CGFloat = 1.0

    // MARK: - Zoom/Pan State

    /// Current zoom scale (1.0 = original size)
    @State private var scale: CGFloat = 1.0
    /// Tracking scale during gesture
    @State private var lastScale: CGFloat = 1.0
    /// Current pan offset
    @State private var offset: CGSize = .zero
    /// Tracking offset during gesture
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            frameView

            if showStats {
                statsOverlay
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .help("Return to window picker")
                .accessibilityIdentifier("backButton")
            }

            ToolbarItemGroup {
                Toggle(isOn: $showStats) {
                    Label("Stats", systemImage: "chart.bar")
                }
                .help("Toggle performance stats")
                .accessibilityIdentifier("statsToggle")

                Button(action: resetZoom) {
                    Label("Reset Zoom", systemImage: "1.magnifyingglass")
                }
                .help("Reset zoom to 1x")
                .disabled(scale == 1.0 && offset == .zero)
                .accessibilityIdentifier("resetZoomButton")

                HStack(spacing: 4) {
                    Button(action: decreaseFontSize) {
                        Image(systemName: "minus")
                    }
                    .accessibilityIdentifier("fontSizeDecrease")
                    Text(String(format: "%.0f%%", fontSizeMultiplier * 100))
                        .font(.caption.monospacedDigit())
                        .frame(width: 40)
                        .accessibilityIdentifier("fontSizeLabel")
                    Button(action: increaseFontSize) {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("fontSizeIncrease")
                }
                .help("Adjust font size")

                if case .running = pipeline.state {
                    Button(action: onStop) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .help("Stop translation")
                    .accessibilityIdentifier("stopButton")
                } else if case .idle = pipeline.state {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .help("Resume translation")
                    .accessibilityIdentifier("playButton")
                }
            }
        }
    }

    // MARK: - Frame Display

    @ViewBuilder
    private var frameView: some View {
        if let frame = pipeline.currentFrame {
            GeometryReader { geometry in
                Image(nsImage: frame.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .gesture(magnifyGesture)
                    .gesture(dragGesture)
            }
            .clipped()
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            waitingView
        }
    }

    // MARK: - Zoom/Pan Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Use lastScale as the base, multiply by gesture magnification
                let newScale = lastScale * value.magnification
                // Clamp to valid range and ensure finite
                scale = min(max(newScale, 1.0), 5.0)
            }
            .onEnded { _ in
                // Store current scale as base for next gesture
                lastScale = scale
                // Reset offset if zoomed out to 1x
                if scale == 1.0 {
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only allow panning when zoomed in
                guard scale > 1.0 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1.0
            offset = .zero
        }
        lastScale = 1.0
        lastOffset = .zero
    }

    private var waitingView: some View {
        VStack(spacing: 16) {
            switch pipeline.state {
            case .idle:
                Button(action: onPlay) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playButton")
                Text("Ready")
                    .font(.headline)
                    .foregroundStyle(.secondary)

            case .starting:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Starting pipeline...")
                    .font(.headline)
                    .foregroundStyle(.secondary)

            case .running:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Waiting for first frame...")
                    .font(.headline)
                    .foregroundStyle(.secondary)

            case .stopping:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Stopping...")
                    .font(.headline)
                    .foregroundStyle(.secondary)

            case .error(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Error")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Retry", action: onPlay)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("retryButton")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("waitingView")
    }

    // MARK: - Font Size Controls

    private func decreaseFontSize() {
        let newValue = max(0.5, fontSizeMultiplier - 0.1)
        fontSizeMultiplier = newValue
        pipeline.fontSizeMultiplier = newValue
    }

    private func increaseFontSize() {
        let newValue = min(2.0, fontSizeMultiplier + 0.1)
        fontSizeMultiplier = newValue
        pipeline.fontSizeMultiplier = newValue
    }

    // MARK: - Stats Overlay

    private var statsOverlay: some View {
        VStack {
            HStack {
                Spacer()
                statsPanel
                    .padding(8)
            }
            Spacer()
        }
    }

    private var statsPanel: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Processing indicator
            if pipeline.isProcessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("processingIndicator")
            }

            if let frame = pipeline.currentFrame {
                Text(frame.performanceDescription)
                    .font(.caption.monospacedDigit())

                Text(String(format: "%.1f eff. FPS", frame.effectiveFPS))
                    .font(.caption.monospacedDigit())
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)

                Text("Frame \(pipeline.frameCount)")
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("frameCountLabel")
            }

            if pipeline.averageProcessingTime > 0 {
                Text(String(format: "Avg: %.0fms", pipeline.averageProcessingTime * 1000))
                    .font(.caption.monospacedDigit())
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("statsPanel")
    }

    private var stateColor: Color {
        switch pipeline.state {
        case .idle:
            return .gray
        case .starting, .stopping:
            return .yellow
        case .running:
            return .green
        case .error:
            return .red
        }
    }
}

#Preview("With Frame") {
    let pipeline = TranslationPipeline()
    return TranslatedWindowView(
        pipeline: pipeline,
        onStop: { print("Stop pressed") },
        onPlay: { print("Play pressed") },
        onBack: { print("Back pressed") }
    )
}

#Preview("Loading") {
    let pipeline = TranslationPipeline()
    return TranslatedWindowView(
        pipeline: pipeline,
        onStop: { print("Stop pressed") },
        onPlay: { print("Play pressed") },
        onBack: { print("Back pressed") }
    )
}
