//
//  xdoubleApp.swift
//  xdouble
//
//  Created by miles on 1/17/26.
//

import SwiftUI

@main
struct xdoubleApp: App {
    /// Application delegate for handling app lifecycle events
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 800, height: 600)
        .commands {
            // Add keyboard shortcuts for common actions
            CommandGroup(after: .appInfo) {
                Button("Check Screen Recording Permission") {
                    checkAndRequestPermission()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }

    /// Check screen recording permission and show alert if not granted.
    private func checkAndRequestPermission() {
        if !CaptureService.hasScreenRecordingPermission() {
            _ = CaptureService.requestScreenRecordingPermission()
        }
    }
}

/// Application delegate for handling lifecycle events and permissions.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for screen recording permission on first launch
        // This triggers the system permission dialog if needed
        if !CaptureService.hasScreenRecordingPermission() {
            // Request permission - this shows the system dialog
            _ = CaptureService.requestScreenRecordingPermission()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Quit the app when the main window is closed
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup on termination if needed
    }
}
