import Foundation

/// DockPeek 1.1.1–1.2.4 kept the Dock up by switching auto-hide off while a preview was open (which made
/// macOS reserve the Dock's space). If one of those versions quit while doing it, auto-hide stayed off:
/// put it back on the next launch. The Dock is now kept up by `DockHoverNudge` instead.
@MainActor
enum DockAutohideLock {
    private typealias SetFunction = @convention(c) (Bool) -> Void
    private static let pendingRestoreKey = "dockAutohidePendingRestore"

    static func restoreAfterCrash() {
        guard UserDefaults.standard.bool(forKey: pendingRestoreKey),
              let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
              let set = dlsym(handle, "CoreDockSetAutoHideEnabled")
        else { return }
        unsafeBitCast(set, to: SetFunction.self)(true)
        UserDefaults.standard.removeObject(forKey: pendingRestoreKey)
        Log.app.info("Restored Dock auto-hide left off by a previous version")
    }
}
