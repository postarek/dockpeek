import Foundation

/// Settings shared between the DockPeek app and its System Settings pane.
/// Both read/write the app's preferences domain; the pane posts `changedNotification` after each write.
public enum DockPeekSettings {
    public static let domain = "local.dockpeek"
    public static let changedNotification = Notification.Name("local.dockpeek.settingsChanged")
    /// Posted by the pane's "Check Now" button; the app runs the update check.
    public static let checkForUpdatesNotification = Notification.Name("local.dockpeek.checkForUpdates")

    public enum Key {
        public static let previewsEnabled = "previewsEnabled"
        public static let activationDelayMs = "activationDelayMs"
        public static let hideDelayMs = "hideDelayMs"
        public static let previewSize = "previewSize"
        public static let includeOtherSpaces = "includeOtherSpaces"
        public static let includeMinimized = "includeMinimized"
        public static let hideOnDockClick = "hideOnDockClick"
        public static let skipSingleWindow = "skipSingleWindow"
        public static let autoCheckUpdates = "autoCheckUpdates"
        public static let keepDockVisible = "keepDockVisible"
    }

    public enum PreviewSize: Int, CaseIterable {
        case small, medium, large

        public var title: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }

        public var maxThumbnail: CGSize {
            switch self {
            case .small: return CGSize(width: 180, height: 120)
            case .medium: return CGSize(width: 240, height: 160)
            case .large: return CGSize(width: 320, height: 213)
            }
        }
    }

    public static let activationDelayRange = 0...2000

    public static let registeredDefaults: [String: Any] = [
        Key.previewsEnabled: true,
        Key.activationDelayMs: 0,
        Key.hideDelayMs: 0,
        Key.previewSize: PreviewSize.medium.rawValue,
        Key.includeOtherSpaces: true,
        Key.includeMinimized: true,
        Key.hideOnDockClick: true,
        Key.skipSingleWindow: false,
        Key.autoCheckUpdates: true,
        Key.keepDockVisible: true,
    ]

    /// The app uses its own standard defaults; any other process (the pane) opens the app's domain by name.
    public static let store: UserDefaults = {
        let defaults = Bundle.main.bundleIdentifier == domain
            ? UserDefaults.standard
            : (UserDefaults(suiteName: domain) ?? .standard)
        defaults.register(defaults: registeredDefaults)
        return defaults
    }()

    public static var previewsEnabled: Bool {
        get { store.bool(forKey: Key.previewsEnabled) }
        set { write(newValue, Key.previewsEnabled) }
    }

    public static var activationDelayMs: Int {
        get { store.integer(forKey: Key.activationDelayMs) }
        set {
            let clamped = min(max(newValue, activationDelayRange.lowerBound), activationDelayRange.upperBound)
            write(clamped, Key.activationDelayMs)
        }
    }

    /// How long the preview stays after the pointer leaves it (and its Dock icon).
    public static var hideDelayMs: Int {
        get { store.integer(forKey: Key.hideDelayMs) }
        set {
            let clamped = min(max(newValue, activationDelayRange.lowerBound), activationDelayRange.upperBound)
            write(clamped, Key.hideDelayMs)
        }
    }

    public static var previewSize: PreviewSize {
        get { PreviewSize(rawValue: store.integer(forKey: Key.previewSize)) ?? .medium }
        set { write(newValue.rawValue, Key.previewSize) }
    }

    public static var includeOtherSpaces: Bool {
        get { store.bool(forKey: Key.includeOtherSpaces) }
        set { write(newValue, Key.includeOtherSpaces) }
    }

    public static var includeMinimized: Bool {
        get { store.bool(forKey: Key.includeMinimized) }
        set { write(newValue, Key.includeMinimized) }
    }

    public static var hideOnDockClick: Bool {
        get { store.bool(forKey: Key.hideOnDockClick) }
        set { write(newValue, Key.hideOnDockClick) }
    }

    public static var skipSingleWindow: Bool {
        get { store.bool(forKey: Key.skipSingleWindow) }
        set { write(newValue, Key.skipSingleWindow) }
    }

    public static var autoCheckUpdates: Bool {
        get { store.bool(forKey: Key.autoCheckUpdates) }
        set { write(newValue, Key.autoCheckUpdates) }
    }

    /// With Dock auto-hide on, keep the Dock shown while the pointer is in a preview.
    public static var keepDockVisible: Bool {
        get { store.bool(forKey: Key.keepDockVisible) }
        set { write(newValue, Key.keepDockVisible) }
    }

    private static func write(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
        store.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            changedNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}
