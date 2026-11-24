import AppKit
import DockPeekShared
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let dockWatcher = DockWatcher()
    private var previewController: PreviewController?
    private let onboarding = PermissionOnboarding()
    private let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockAutohideLock.restoreAfterCrash()
        SettingsPaneInstaller.installIfNeeded()
        enableLoginItemOnFirstLaunch()
        setupStatusItem()
        onboarding.startIfNeeded()
        Log.app.info("Launched. accessibility=\(Permissions.hasAccessibility) screenRecording=\(Permissions.hasScreenRecording)")

        let controller = PreviewController()
        previewController = controller
        dockWatcher.onHoverChange = { [weak controller] item in controller?.handleHover(item) }
        dockWatcher.start()
        updater.start()

        // Written by the System Settings pane (another process).
        DistributedNotificationCenter.default().addObserver(
            forName: DockPeekSettings.changedNotification, object: nil, queue: .main
        ) { [weak controller] _ in
            MainActor.assumeIsolated {
                DockPeekSettings.store.synchronize()
                if !DockPeekSettings.previewsEnabled { controller?.hide() }
                if !DockPeekSettings.keepDockVisible { DockHoverNudge.release() }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: DockPeekSettings.checkForUpdatesNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updater.checkNow() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DockHoverNudge.release()
    }

    /// Like HyperDock, start at login by default; the user can turn it off in the menu afterwards.
    private func enableLoginItemOnFirstLaunch() {
        let key = "didEnableLoginItemOnFirstLaunch"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "DockPeek")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: dockWatcher.isAttached ? "DockPeek is active" : "DockPeek is waiting for permissions", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(permissionItem(title: "Accessibility", granted: Permissions.hasAccessibility,
                                    action: #selector(openAccessibility)))
        menu.addItem(permissionItem(title: "Screen Recording", granted: Permissions.hasScreenRecording,
                                    action: #selector(openScreenRecording)))
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.isEnabled = SettingsPaneInstaller.isInstalled
        menu.addItem(settings)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let update = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        menu.addItem(.separator())

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "Version \(version) (\(build))", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quit = NSMenuItem(title: "Quit DockPeek", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func permissionItem(title: String, granted: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title): \(granted ? "granted" : "not granted — Open Settings…")",
                              action: granted ? nil : action, keyEquivalent: "")
        item.target = self
        item.state = granted ? .on : .off
        item.isEnabled = !granted
        return item
    }

    @objc private func openSettings() { NSWorkspace.shared.open(SettingsPaneInstaller.installedURL) }
    @objc private func openAccessibility() { onboarding.startIfNeeded() }
    @objc private func openScreenRecording() { onboarding.startIfNeeded() }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the Open at Login setting"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func checkForUpdates() { updater.checkNow() }
    @objc private func quit() { NSApp.terminate(nil) }
}
