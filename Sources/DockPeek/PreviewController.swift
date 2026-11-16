import AppKit
import DockPeekShared
import ScreenCaptureKit
import SwiftUI

final class PreviewPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PreviewController {
    private let panel = PreviewPanel()
    private let model = PreviewModel()
    private let hostingView: FirstMouseHostingView<PreviewView>

    private var shownItem: DockItem?
    private var hoveredItem: DockItem?
    private var suppressedItem: DockItem?
    private var pendingShow: DispatchWorkItem?
    private var loadTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var outsideSince: Date?
    private var mouseDownMonitor: Any?

    private static let gap: CGFloat = 6
    private static let hideDelay: TimeInterval = 0.3

    init() {
        hostingView = FirstMouseHostingView(rootView: PreviewView(model: model))
        panel.contentView = hostingView
        model.onSelect = { [weak self] entry in
            self?.hide()
            WindowActions.focus(entry)
        }
        model.onClose = { [weak self] entry in self?.close(entry) }

        // Clicking anywhere else (including the Dock icon itself) dismisses the preview.
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, self.panel.isVisible else { return }
                // Clicking the Dock icon itself keeps the preview when the user turned that off.
                if !DockPeekSettings.hideOnDockClick, self.hoveredItem != nil { return }
                self.suppressedItem = self.shownItem
                self.hide()
            }
        }
    }

    // MARK: - Hover handling

    func handleHover(_ item: DockItem?) {
        pendingShow?.cancel()
        hoveredItem = item
        guard DockPeekSettings.previewsEnabled else { return hide() }
        if item != suppressedItem { suppressedItem = nil }
        guard let item, item != suppressedItem else { return }
        if panel.isVisible, item == shownItem { return }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.show(for: item) }
        }
        pendingShow = work
        // Activation delay so sweeping across the Dock does not flash previews.
        let delay = panel.isVisible ? 0.05 : Double(DockPeekSettings.activationDelayMs) / 1000
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func show(for item: DockItem) {
        guard hoveredItem == item, isMouseOver(item) else { return }
        guard let app = item.runningApplication else { return hide() }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let (entries, scWindows) = await WindowProvider.windows(
                for: app,
                includeMinimized: DockPeekSettings.includeMinimized,
                includeOtherSpaces: DockPeekSettings.includeOtherSpaces
            )
            guard let self, !Task.isCancelled else { return }
            // Listing windows takes a moment: by now the pointer may have left the icon (and the Dock may
            // have hidden). Showing the panel anyway would put it under the pointer and keep it open.
            guard self.isMouseOver(item) || self.isMouseInsidePanel else {
                Log.app.debug("Pointer left \(item.title, privacy: .public) before its preview was ready")
                return self.hide()
            }
            let tooFew = entries.isEmpty || (DockPeekSettings.skipSingleWindow && entries.count == 1)
            Log.app.debug("\(app.localizedName ?? "?", privacy: .public): \(entries.count) windows")
            guard !tooFew else { return self.hide() }

            self.present(entries: entries, app: app, item: item)
            await self.loadThumbnails(entries: entries, scWindows: scWindows)
        }
    }

    private func present(entries: [WindowEntry], app: NSRunningApplication, item: DockItem) {
        let orientation = DockOrientation.current
        let screen = NSScreen.screens.first { $0.frame.intersects(item.frame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        model.appName = app.localizedName ?? item.title
        model.appIcon = app.icon
        model.vertical = orientation != .bottom
        model.thumbnailMaxSize = Self.thumbnailSize(count: entries.count, orientation: orientation, visible: visible)
        model.windows = entries
        shownItem = item

        layoutPanel(anchor: item.frame, orientation: orientation, visible: visible)
        if !panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        startPolling()
    }

    private func layoutPanel(anchor: CGRect, orientation: DockOrientation, visible: CGRect) {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        var origin: CGPoint
        switch orientation {
        case .bottom:
            origin = CGPoint(x: anchor.midX - size.width / 2, y: max(anchor.maxY, visible.minY) + Self.gap)
        case .left:
            origin = CGPoint(x: max(anchor.maxX, visible.minX) + Self.gap, y: anchor.midY - size.height / 2)
        case .right:
            origin = CGPoint(x: min(anchor.minX, visible.maxX) - size.width - Self.gap, y: anchor.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private static func thumbnailSize(count: Int, orientation: DockOrientation, visible: CGRect) -> CGSize {
        let base = DockPeekSettings.previewSize.maxThumbnail
        let perCardChrome: CGFloat = 20
        let n = CGFloat(max(count, 1))
        switch orientation {
        case .bottom:
            let width = min(base.width, (visible.width - 60) / n - perCardChrome)
            return CGSize(width: max(width, 90), height: base.height * max(width, 90) / base.width)
        case .left, .right:
            let height = min(base.height, (visible.height - 80) / n - perCardChrome - 20)
            return CGSize(width: base.width * max(height, 60) / base.height, height: max(height, 60))
        }
    }

    private func loadThumbnails(entries: [WindowEntry], scWindows: [CGWindowID: SCWindow]) async {
        let maxSize = model.thumbnailMaxSize
        await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
            for entry in entries where !entry.isMinimized {
                guard let window = scWindows[entry.id] else { continue }
                group.addTask { (entry.id, await WindowProvider.thumbnail(for: window, fitting: maxSize)) }
            }
            for await (id, image) in group {
                guard !Task.isCancelled, let image,
                      let index = model.windows.firstIndex(where: { $0.id == id }) else { continue }
                model.windows[index].thumbnail = image
            }
        }
    }

    private func close(_ entry: WindowEntry) {
        guard WindowActions.close(entry) else { return }
        model.windows.removeAll { $0.id == entry.id }
        if model.windows.isEmpty {
            hide()
        } else if let item = shownItem {
            let screen = NSScreen.screens.first { $0.frame.intersects(item.frame) } ?? NSScreen.main
            layoutPanel(anchor: item.frame, orientation: .current, visible: screen?.visibleFrame ?? .zero)
        }
    }

    func hide() {
        pendingShow?.cancel()
        loadTask?.cancel()
        pollTimer?.invalidate()
        pollTimer = nil
        outsideSince = nil
        shownItem = nil
        panel.orderOut(nil)
        model.windows = []
    }

    // MARK: - Auto-hide

    private var isMouseInsidePanel: Bool {
        panel.isVisible && panel.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.checkMouse() }
        }
    }

    /// The Dock does not always report that the pointer left an icon (e.g. when it auto-hides or the
    /// pointer leaves quickly), so the AX selection alone can be stale: confirm with the pointer position.
    private func isMouseOver(_ item: DockItem) -> Bool {
        var area = item.frame.insetBy(dx: -6, dy: -6)
        // Extend to the screen edge the Dock is attached to (covers the gap below/beside the icon).
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(item.frame) }) {
            let edge = screen.frame
            switch DockOrientation.current {
            case .bottom: area = area.union(CGRect(x: area.minX, y: edge.minY, width: area.width, height: 1))
            case .left: area = area.union(CGRect(x: edge.minX, y: area.minY, width: 1, height: area.height))
            case .right: area = area.union(CGRect(x: edge.maxX - 1, y: area.minY, width: 1, height: area.height))
            }
        }
        return area.contains(NSEvent.mouseLocation)
    }

    private func checkMouse() {
        let hovered = hoveredItem.flatMap { isMouseOver($0) ? $0 : nil }
        if isMouseInsidePanel || (hovered != nil && hovered == shownItem) {
            outsideSince = nil
            return
        }
        // A different Dock icon is hovered: its own show() will replace the content.
        if hovered != nil, hovered != suppressedItem { outsideSince = nil; return }
        let since = outsideSince ?? Date()
        outsideSince = since
        if Date().timeIntervalSince(since) >= Self.hideDelay { hide() }
    }
}
