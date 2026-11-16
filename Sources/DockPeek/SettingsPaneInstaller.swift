import Foundation

/// The System Settings pane ships inside the app (Contents/Resources/DockPeek.prefPane) and is copied to
/// ~/Library/PreferencePanes on launch whenever it is missing or a different build. This keeps a single
/// installer (drag the app or run the .pkg) and updates the pane together with the app.
enum SettingsPaneInstaller {
    static let installedURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/PreferencePanes/DockPeek.prefPane")

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: installedURL.path) }

    static func installIfNeeded() {
        guard let bundled = Bundle.main.url(forResource: "DockPeek", withExtension: "prefPane") else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: installedURL.path), buildID(of: installedURL) == buildID(of: bundled) {
            return
        }
        do {
            try fileManager.createDirectory(at: installedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: installedURL.path) {
                try fileManager.removeItem(at: installedURL)
            }
            try fileManager.copyItem(at: bundled, to: installedURL)
            Log.app.info("Installed Settings pane \(buildID(of: bundled) ?? "?", privacy: .public)")
        } catch {
            Log.app.error("Settings pane install failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Read straight from Info.plist: `Bundle(url:)` caches and would return stale values after a replace.
    private static func buildID(of pane: URL) -> String? {
        let plist = NSDictionary(contentsOf: pane.appendingPathComponent("Contents/Info.plist"))
        guard let short = plist?["CFBundleShortVersionString"] as? String,
              let build = plist?["CFBundleVersion"] as? String else { return nil }
        return "\(short) (\(build))"
    }
}
