import Foundation

/// Keeps an auto-hiding Dock on screen while a preview is open: moving the pointer from the Dock into the
/// preview would otherwise make the Dock hide and leave the preview floating on its own.
///
/// Uses the Dock's private CoreDock calls (the same switch as System Settings › Desktop & Dock, applied
/// without restarting the Dock). The user's setting is always put back; if DockPeek quits while holding the
/// Dock, `restoreAfterCrash()` puts it back on the next launch.
@MainActor
enum DockAutohideLock {
    private typealias GetFunction = @convention(c) () -> Bool
    private typealias SetFunction = @convention(c) (Bool) -> Void

    private static let pendingRestoreKey = "dockAutohidePendingRestore"
    private static var isHolding = false

    private static let functions: (get: GetFunction, set: SetFunction)? = {
        guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
              let get = dlsym(handle, "CoreDockGetAutoHideEnabled"),
              let set = dlsym(handle, "CoreDockSetAutoHideEnabled")
        else { return nil }
        return (unsafeBitCast(get, to: GetFunction.self), unsafeBitCast(set, to: SetFunction.self))
    }()

    /// Turns auto-hide off (only if it is on) until `release()`.
    static func hold() {
        guard !isHolding, let functions, functions.get() else { return }
        UserDefaults.standard.set(true, forKey: pendingRestoreKey)
        functions.set(false)
        isHolding = true
    }

    static func release() {
        guard isHolding, let functions else { return }
        functions.set(true)
        isHolding = false
        UserDefaults.standard.removeObject(forKey: pendingRestoreKey)
    }

    static func restoreAfterCrash() {
        guard UserDefaults.standard.bool(forKey: pendingRestoreKey), let functions else { return }
        functions.set(true)
        UserDefaults.standard.removeObject(forKey: pendingRestoreKey)
        Log.app.info("Restored Dock auto-hide left off by a previous run")
    }
}
