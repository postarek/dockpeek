import AppKit

/// Keeps an auto-hiding Dock up while the pointer is in a preview by telling the Dock (and only the Dock)
/// that the pointer is still over the shown icon. The real pointer doesn't move and auto-hide stays on, so
/// macOS doesn't reserve the Dock's space: desktop icons and full-screen-sized windows stay as they are.
///
/// The catch (seen in 1.2.4): the Dock then waits for the pointer to leave it, which the system only
/// reports when the real pointer crosses the Dock's edge, so it stayed up. `release()` makes that happen:
/// it sends the real pointer over the held icon and straight back, a single frame long.
@MainActor
enum DockHoverNudge {
    private static var heldPoint: CGPoint?
    /// Dock hover reports caused by that pointer pass, which must not reopen a preview.
    private(set) static var ignoreHoverUntil = Date.distantPast

    private static var dockPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    }

    /// Keeps the Dock up; `point` (Cocoa screen coordinates) is on the shown icon.
    static func hold(at point: CGPoint) {
        heldPoint = point
        guard let pid = dockPID, let event = mouseMoved(to: point, source: nil) else { return }
        event.postToPid(pid)
    }

    /// Lets the Dock hide again (unless the real pointer is over it).
    static func release() {
        guard let point = heldPoint else { return }
        heldPoint = nil
        let real = NSEvent.mouseLocation
        ignoreHoverUntil = Date().addingTimeInterval(0.3)
        let source = CGEventSource(stateID: .hidSystemState)
        mouseMoved(to: point, source: source)?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
            mouseMoved(to: real, source: source)?.post(tap: .cghidEventTap)
        }
        Log.app.debug("Released the Dock with a pointer pass")
    }

    /// `point` in Cocoa coordinates (origin at the bottom-left of the main screen).
    private static func mouseMoved(to point: CGPoint, source: CGEventSource?) -> CGEvent? {
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return nil }
        return CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                       mouseCursorPosition: CGPoint(x: point.x, y: mainHeight - point.y), mouseButton: .left)
    }
}
