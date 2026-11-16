import AppKit
import ApplicationServices
import SwiftUI

/// Guided setup: opens the exact System Settings page for each missing permission (with DockPeek already
/// listed), so the user only has to turn the switch on. Advances by itself as permissions are granted.
@MainActor
final class PermissionOnboarding: ObservableObject {
    @Published private(set) var accessibility = Permissions.hasAccessibility
    @Published private(set) var screenRecording = Permissions.hasScreenRecording
    @Published private(set) var finished = false

    private var window: NSWindow?
    private var pollTimer: Timer?

    var isComplete: Bool { accessibility && screenRecording }

    func startIfNeeded() {
        refreshValues()
        guard !isComplete else { return }
        finished = false
        showWindow()
        requestNextPermission()
        startPolling()
    }

    // MARK: - Steps

    func requestNextPermission() {
        if !accessibility {
            requestAccessibility()
        } else if !screenRecording {
            requestScreenRecording()
        }
    }

    func requestAccessibility() {
        // Adds DockPeek (switched off) to the Accessibility list; then show that list.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        Permissions.openAccessibilitySettings()
    }

    func requestScreenRecording() {
        // Adds DockPeek to the Screen Recording list (macOS only shows its own prompt the first time).
        CGRequestScreenCaptureAccess()
        Permissions.openScreenRecordingSettings()
    }

    /// Screen Recording is only picked up by a new process; macOS usually offers "Quit & Reopen" itself.
    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    func dismiss() {
        pollTimer?.invalidate()
        pollTimer = nil
        window?.orderOut(nil)
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.poll() }
        }
    }

    private func poll() {
        let hadAccessibility = accessibility
        refreshValues()
        if isComplete {
            complete()
        } else if !hadAccessibility && accessibility {
            // Accessibility just turned on: move straight to Screen Recording.
            requestScreenRecording()
        }
    }

    private func refreshValues() {
        accessibility = Permissions.hasAccessibility
        screenRecording = Permissions.hasScreenRecording
    }

    private func complete() {
        pollTimer?.invalidate()
        pollTimer = nil
        finished = true
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated { self?.window?.orderOut(nil) }
        }
    }

    // MARK: - Window

    private func showWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "DockPeek Setup"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: OnboardingView(onboarding: self))
            self.window = window
        }
        guard let window else { return }
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 420, height: 300))
        // Top-right corner, so System Settings (centered) stays visible next to it.
        if let visible = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: visible.maxX - window.frame.width - 24,
                                          y: visible.maxY - window.frame.height - 24))
        }
        NSApp.activate()
        window.orderFrontRegardless()
    }
}

private struct OnboardingView: View {
    @ObservedObject var onboarding: PermissionOnboarding

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(onboarding.finished ? "You're all set" : "Set up DockPeek")
                        .font(.system(size: 17, weight: .semibold))
                    Text(onboarding.finished
                         ? "Hover any app in the Dock to see its windows."
                         : "System Settings is open on the right page. Just turn DockPeek on.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 10) {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Lets DockPeek see which Dock icon is under the pointer.",
                    granted: onboarding.accessibility,
                    isCurrent: !onboarding.accessibility,
                    action: onboarding.requestAccessibility
                )
                PermissionRow(
                    title: "Screen & System Audio Recording",
                    detail: "Lets DockPeek draw the window thumbnails.",
                    granted: onboarding.screenRecording,
                    isCurrent: onboarding.accessibility && !onboarding.screenRecording,
                    action: onboarding.requestScreenRecording
                )
            }

            if onboarding.accessibility && !onboarding.screenRecording {
                Text("After turning it on, choose “Quit & Reopen” if macOS asks.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                if onboarding.finished {
                    Button("Done", action: onboarding.dismiss)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Later", action: onboarding.dismiss)
                    if onboarding.accessibility && !onboarding.screenRecording {
                        Button("Reopen DockPeek", action: onboarding.relaunch)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(20)
        .padding(.top, 8)
        .frame(width: 420)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : (isCurrent ? "arrow.right.circle.fill" : "circle"))
                .font(.system(size: 20))
                .foregroundStyle(granted ? Color.green : (isCurrent ? Color.accentColor : Color.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Open Settings", action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04))
        )
    }
}
