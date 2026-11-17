import AppKit

/// Keeps an auto-hiding Dock up while the pointer is in a preview by telling the Dock (and
/// only the Dock) that the pointer is still over the shown icon. The real pointer doesn't move, and auto-hide
/// stays on, so macOS doesn't reserve the Dock's space and desktop icons stay put.
@MainActor
enum DockHoverNudge {
    private static var dockPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    }

    /// `point` is in Cocoa screen coordinates (origin bottom-left of the main screen).
    static func nudge(at point: CGPoint) {
        guard let pid = dockPID, let mainHeight = NSScreen.screens.first?.frame.height else { return }
        let cgPoint = CGPoint(x: point.x, y: mainHeight - point.y)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                  mouseCursorPosition: cgPoint, mouseButton: .left)
        else { return }
        event.postToPid(pid)
    }
}
