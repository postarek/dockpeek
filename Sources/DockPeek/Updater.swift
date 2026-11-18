import AppKit
import DockPeekShared

/// Self-update from the GitHub releases of the public repository.
///
/// Each release carries `DockPeek-<version>.zip` (the app) and `DockPeek-<version>.pkg` (for new users).
/// The updater downloads the zip, checks that it is DockPeek with a valid signature, swaps the bundle in
/// place and relaunches. The designated requirement is pinned to the bundle identifier, so macOS keeps the
/// Accessibility/Screen Recording grants across updates.
@MainActor
final class Updater {
    static let repository = "postarek/dockpeek"
    private static let checkInterval: TimeInterval = 12 * 60 * 60
    private static let skippedVersionKey = "skippedUpdateVersion"

    private var timer: Timer?
    private var isBusy = false

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            MainActor.assumeIsolated { self?.checkInBackground() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.checkInBackground() }
        }
    }

    func checkNow() {
        Task { await check(userInitiated: true) }
    }

    private func checkInBackground() {
        guard DockPeekSettings.autoCheckUpdates else { return }
        Task { await check(userInitiated: false) }
    }

    // MARK: - Check

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let body: String?
        let htmlURL: URL
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
            case assets
        }

        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    }

    private func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let release: Release
        do {
            release = try await fetchLatestRelease()
        } catch {
            Log.app.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            if userInitiated {
                showAlert("Couldn't check for updates", error.localizedDescription)
            }
            return
        }

        let latest = release.version
        Log.app.info("Update check: installed \(Self.currentVersion, privacy: .public), latest \(latest, privacy: .public)")
        guard Self.isVersion(latest, newerThan: Self.currentVersion) else {
            if userInitiated {
                showAlert("You're up to date", "DockPeek \(Self.currentVersion) is the latest version.")
            }
            return
        }
        if !userInitiated, UserDefaults.standard.string(forKey: Self.skippedVersionKey) == latest { return }

        switch askToInstall(release) {
        case .install:
            await install(release)
        case .skip:
            UserDefaults.standard.set(latest, forKey: Self.skippedVersionKey)
        case .later:
            break
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DockPeek/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.message("GitHub answered with status \(http.statusCode).")
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    /// Compares "X.Y.Z" versions; a test build "X.Y.Z<letter>" comes before the final X.Y.Z.
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        func parse(_ version: String) -> (numbers: [Int], test: String?) {
            let numbers = version.prefix { $0.isNumber || $0 == "." }
            let suffix = version.dropFirst(numbers.count)
            return (numbers.split(separator: ".").map { Int($0) ?? 0 }, suffix.isEmpty ? nil : String(suffix))
        }
        let a = parse(lhs), b = parse(rhs)
        for i in 0..<max(a.numbers.count, b.numbers.count) {
            let x = i < a.numbers.count ? a.numbers[i] : 0
            let y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x > y }
        }
        switch (a.test, b.test) {
        case (nil, nil): return false
        case (nil, _): return true        // final is newer than its test builds
        case (_, nil): return false
        case let (x?, y?): return x > y
        }
    }

    // MARK: - Prompt

    private enum Choice { case install, later, skip }

    private func askToInstall(_ release: Release) -> Choice {
        let alert = NSAlert()
        alert.messageText = "DockPeek \(release.version) is available"
        var text = "You have version \(Self.currentVersion). Install the update now? DockPeek will restart by itself."
        if let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            let short = notes.count > 600 ? String(notes.prefix(600)) + "…" : notes
            text += "\n\nWhat's new:\n" + short
        }
        alert.informativeText = text
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .install
        case .alertThirdButtonReturn: return .skip
        default: return .later
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    // MARK: - Install

    private enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): return text }
        }
    }

    private func install(_ release: Release) async {
        do {
            let newApp = try await download(release)
            try replaceInstalledApp(with: newApp)
            Log.app.info("Updated to \(release.version, privacy: .public); relaunching")
            relaunch()
        } catch {
            Log.app.error("Update failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Couldn't install the update"
            alert.informativeText = error.localizedDescription
                + "\n\nYou can download it from the DockPeek page on GitHub instead."
            alert.addButton(withTitle: "Open Download Page")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    /// Downloads and unpacks the release zip; returns the verified DockPeek.app inside it.
    private func download(_ release: Release) async throws -> URL {
        let assetName = "DockPeek-\(release.version).zip"
        guard let asset = release.assets.first(where: { $0.name == assetName }) else {
            throw UpdateError.message("The release has no \(assetName).")
        }

        let (tempFile, response) = try await URLSession.shared.download(from: asset.browserDownloadURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.message("The download failed (status \(http.statusCode)).")
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockPeekUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let zip = workDir.appendingPathComponent(assetName)
        try FileManager.default.moveItem(at: tempFile, to: zip)

        try run("/usr/bin/ditto", ["-x", "-k", zip.path, workDir.path], failure: "Couldn't unpack the update.")
        let app = workDir.appendingPathComponent("DockPeek.app")

        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info?["CFBundleShortVersionString"] as? String == release.version
        else { throw UpdateError.message("The downloaded file isn't the expected DockPeek version.") }

        // Must be intact and keep the identifier-based requirement that the permissions are tied to.
        try run("/usr/bin/codesign",
                ["--verify", "--deep", "--strict", "-R=identifier \"\(DockPeekSettings.domain)\"", app.path],
                failure: "The update's signature is invalid.")
        return app
    }

    private func replaceInstalledApp(with newApp: URL) throws {
        let target = Bundle.main.bundleURL
        let owner = try? FileManager.default.attributesOfItem(atPath: target.appendingPathComponent("Contents").path)[.ownerAccountID] as? Int
        if owner == Int(getuid()) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
        } else {
            // Installed by the .pkg (owned by root): ask for an administrator password once, and hand the
            // app to the user so later updates don't need it.
            let user = NSUserName()
            let command = "rm -rf \(shellQuoted(target.path)) && /usr/bin/ditto \(shellQuoted(newApp.path)) \(shellQuoted(target.path)) && /usr/sbin/chown -R \(shellQuoted(user)) \(shellQuoted(target.path))"
            let source = "do shell script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
            var errorInfo: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Permission denied."
                throw UpdateError.message(message)
            }
        }
    }

    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // A pane loaded by System Settings would show blank after the app replaces it on launch.
        task.arguments = ["-c", "sleep 1; /usr/bin/pkill -f legacyLoader-arm64; /usr/bin/open \(shellQuoted(Bundle.main.bundlePath))"]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func run(_ executable: String, _ arguments: [String], failure: String) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw UpdateError.message(failure) }
    }

    private func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
