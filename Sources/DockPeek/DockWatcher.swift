import AppKit
import ApplicationServices

struct DockItem: Equatable {
    let title: String
    let appURL: URL?
    /// Icon frame in Cocoa screen coordinates.
    let frame: CGRect

    static func == (lhs: DockItem, rhs: DockItem) -> Bool {
        lhs.title == rhs.title && lhs.appURL?.standardizedFileURL == rhs.appURL?.standardizedFileURL
    }

    var runningApplication: NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        if let url = appURL?.standardizedFileURL,
           let match = apps.first(where: { $0.bundleURL?.standardizedFileURL == url }) {
            return match
        }
        return apps.first { $0.localizedName == title && $0.activationPolicy == .regular }
    }
}

enum DockOrientation {
    case bottom, left, right

    static var current: DockOrientation {
        switch UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }
}

/// Watches the Dock's AX list: the Dock "selects" the item under the mouse while hovering.
@MainActor
final class DockWatcher {
    var onHoverChange: ((DockItem?) -> Void)?

    private var observer: AXObserver?
    private var dockList: AXUIElement?
    private var retryTimer: Timer?
    private nonisolated static let dockBundleID = "com.apple.dock"

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.dockBundleID else { return }
            // Dock was restarted (e.g. `killall Dock`): re-attach once it is ready.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                MainActor.assumeIsolated { self?.attach() }
            }
        }
        attach()
    }

    var isAttached: Bool { observer != nil }

    private func attach() {
        detach()
        guard Permissions.hasAccessibility,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleID).first
        else { return scheduleRetry() }

        let dockApp = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = dockApp.elements(kAXChildrenAttribute).first(where: { $0.role == kAXListRole })
        else { return scheduleRetry() }

        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<DockWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.selectionChanged() }
        }

        var newObserver: AXObserver?
        guard AXObserverCreate(dock.processIdentifier, callback, &newObserver) == .success, let newObserver
        else { return scheduleRetry() }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(newObserver, list, kAXSelectedChildrenChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)

        observer = newObserver
        dockList = list
        retryTimer?.invalidate()
        retryTimer = nil
        Log.app.info("Attached to Dock (pid \(dock.processIdentifier))")
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        dockList = nil
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        Log.app.info("Dock attach failed (accessibility: \(Permissions.hasAccessibility)); retrying")
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.attach()
            }
        }
    }

    private func selectionChanged() {
        guard let list = dockList,
              let selected = list.elements(kAXSelectedChildrenAttribute).first,
              selected.subrole == "AXApplicationDockItem",
              let axFrame = selected.axFrame
        else {
            onHoverChange?(nil)
            return
        }
        let item = DockItem(
            title: selected.title ?? "",
            appURL: selected.url(kAXURLAttribute),
            frame: ScreenGeometry.cocoaRect(fromAX: axFrame)
        )
        Log.app.debug("Hovering Dock item \(item.title, privacy: .public)")
        onHoverChange?(item)
    }
}
