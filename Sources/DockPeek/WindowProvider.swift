import AppKit
import ApplicationServices
import ScreenCaptureKit

struct WindowEntry: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let size: CGSize
    let isMinimized: Bool
    var thumbnail: NSImage?
}

enum WindowProvider {
    /// Lists the "real" windows of an app: on-screen ones, minimized ones and titled ones on other Spaces.
    static func windows(
        for app: NSRunningApplication,
        includeMinimized: Bool,
        includeOtherSpaces: Bool
    ) async -> (entries: [WindowEntry], scWindows: [CGWindowID: SCWindow]) {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        else { return ([], [:]) }

        let pid = app.processIdentifier
        let appHidden = app.isHidden
        let axWindows = await MainActor.run { axWindowStates(pid: pid) }

        var entries: [WindowEntry] = []
        var map: [CGWindowID: SCWindow] = [:]
        for window in content.windows {
            guard window.owningApplication?.processID == pid,
                  window.windowLayer == 0,
                  window.frame.width >= 100, window.frame.height >= 60
            else { continue }

            let axState = axWindows[window.windowID]
            let title = window.title ?? ""
            // Off-screen windows without AX presence and without a title are usually internal helpers.
            guard window.isOnScreen || axState != nil || !title.isEmpty else { continue }

            let minimizedOrHidden = !window.isOnScreen && axState != nil && (axState?.minimized == true || appHidden)
            // AX only reports windows of the current Space, so off-screen + no AX = another Space.
            let onOtherSpace = !window.isOnScreen && axState == nil
            if minimizedOrHidden && !includeMinimized { continue }
            if onOtherSpace && !includeOtherSpaces { continue }

            entries.append(WindowEntry(
                id: window.windowID,
                pid: pid,
                title: title.isEmpty ? (app.localizedName ?? "") : title,
                size: window.frame.size,
                isMinimized: minimizedOrHidden
            ))
            map[window.windowID] = window
        }
        // Keep the AX (front-to-back) order when available, then the remaining ones.
        entries.sort { lhs, rhs in
            let l = axWindows[lhs.id]?.index ?? Int.max
            let r = axWindows[rhs.id]?.index ?? Int.max
            return l == r ? lhs.id < rhs.id : l < r
        }
        return (entries, map)
    }

    static func thumbnail(for window: SCWindow, fitting maxSize: CGSize) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let ratio = min(maxSize.width / window.frame.width, maxSize.height / window.frame.height, 1)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(window.frame.width * ratio * scale))
        config.height = max(1, Int(window.frame.height * ratio * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = true

        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale,
                                                    height: CGFloat(image.height) / scale))
    }

    private struct AXWindowState { let index: Int; let minimized: Bool }

    @MainActor
    private static func axWindowStates(pid: pid_t) -> [CGWindowID: AXWindowState] {
        let app = AXUIElementCreateApplication(pid)
        var result: [CGWindowID: AXWindowState] = [:]
        for (index, window) in app.elements(kAXWindowsAttribute).enumerated() {
            guard let id = window.windowID else { continue }
            result[id] = AXWindowState(index: index, minimized: window.bool(kAXMinimizedAttribute) ?? false)
        }
        return result
    }
}

@MainActor
enum WindowActions {
    static func axWindow(pid: pid_t, id: CGWindowID) -> AXUIElement? {
        AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute).first { $0.windowID == id }
    }

    static func focus(_ entry: WindowEntry) {
        let app = NSRunningApplication(processIdentifier: entry.pid)
        let window = axWindow(pid: entry.pid, id: entry.id)
        if let window, window.bool(kAXMinimizedAttribute) == true {
            window.set(kAXMinimizedAttribute, kCFBooleanFalse)
        }
        app?.activate()
        guard let window else { return }
        raise(window)
        // Activation may bring another window forward right after; raise again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { raise(window) }
    }

    private nonisolated static func raise(_ window: AXUIElement) {
        window.set(kAXMainAttribute, kCFBooleanTrue)
        window.perform(kAXRaiseAction)
    }

    @discardableResult
    static func close(_ entry: WindowEntry) -> Bool {
        guard let window = axWindow(pid: entry.pid, id: entry.id),
              let button = window.element(kAXCloseButtonAttribute)
        else { return false }
        return button.perform(kAXPressAction)
    }
}
