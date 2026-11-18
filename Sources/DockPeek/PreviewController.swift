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
        // Always dark, like the Dock, whatever the system appearance.
        appearance = NSAppearance(named: .darkAqua)
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
    private var moveMonitors: [Any] = []
    private var prewarmTimer: Timer?

    /// Within reach of the Dock's screen edge (where hovering an icon is about to happen).
    private static var isPointerNearDock: Bool {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })?.frame else { return false }
        let reach: CGFloat = 160
        switch DockOrientation.current {
        case .bottom: return mouse.y - screen.minY < reach
        case .left: return mouse.x - screen.minX < reach
        case .right: return screen.maxX - mouse.x < reach
        }
    }

    /// Recently captured thumbnails, so switching between Dock icons shows the windows right away
    /// (the fresh capture replaces them a moment later).
    private var thumbnailCache: [CGWindowID: NSImage] = [:]

    /// Whether the preview is shown (or fading in); false as soon as it starts fading out.
    private var isPresented = false
    /// Just enough to soften the preview appearing and disappearing.
    private static let fadeInStartAlpha: CGFloat = 0.4
    private static let fadeInDuration: TimeInterval = 0.12
    private static let fadeOutDuration: TimeInterval = 0.1

    private func fade(to alpha: CGFloat, duration: TimeInterval, completion: (@MainActor @Sendable () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }, completionHandler: {
            guard let completion else { return }
            MainActor.assumeIsolated { completion() }
        })
    }

    /// Distance between the resting Dock icon and the preview body: small, so there is almost nothing to cross.
    private static let gap: CGFloat = 10

    init() {
        hostingView = FirstMouseHostingView(rootView: PreviewView(model: model))
        panel.contentView = hostingView
        model.onSelect = { [weak self] entry in
            self?.hide()
            WindowActions.focus(entry)
        }
        model.onClose = { [weak self] entry in self?.close(entry) }

        // React to the pointer as it moves (the timer is only a fallback), so the preview leaves together
        // with the Dock instead of a beat later.
        let onMove: (NSEvent) -> Void = { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, self.isPresented else { return }
                self.checkMouse()
            }
        }
        moveMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: onMove),
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
                onMove(event)
                return event
            },
        ].compactMap { $0 }

        // Keep the window list ready while the pointer is near the Dock.
        prewarmTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard DockPeekSettings.previewsEnabled, Self.isPointerNearDock,
                      ShareableContentCache.age > 1 else { return }
                Task { await ShareableContentCache.refresh() }
            }
        }

        // Clicking anywhere else (including the Dock icon itself) dismisses the preview.
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self, self.isPresented else { return }
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
        if isPresented, item == shownItem { return }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.show(for: item) }
        }
        pendingShow = work
        // Optional activation delay, so sweeping across the Dock does not flash previews. Without one the
        // preview opens together with the hover (and covers the Dock's own name label right away).
        let delay = Double(DockPeekSettings.activationDelayMs) / 1000
        if delay <= 0 || isPresented {
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func show(for item: DockItem) {
        guard hoveredItem == item, isMouseOver(item) else { return }
        guard let app = item.runningApplication else { return hide() }

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            // Open from the window list kept ready near the Dock, so the preview appears with the hover;
            // then check a fresh list and update the preview if windows came or went.
            let cached = ShareableContentCache.age < Self.cachedListMaxAge ? ShareableContentCache.content : nil
            var shown: [CGWindowID] = []
            if let cached {
                guard let self, !Task.isCancelled else { return }
                let list = self.windowList(for: app, in: cached)
                guard self.presentIfStillHovering(list, app: app, item: item) else { return }
                shown = list.entries.map(\.id)
            }
            guard let fresh = await ShareableContentCache.refresh() else { return }
            guard let self, !Task.isCancelled else { return }
            let list = self.windowList(for: app, in: fresh)
            if cached == nil || list.entries.map(\.id) != shown {
                guard self.presentIfStillHovering(list, app: app, item: item) else { return }
            }
            await self.loadThumbnails(entries: list.entries, scWindows: list.scWindows)
        }
    }

    private static let cachedListMaxAge: TimeInterval = 5

    private func windowList(for app: NSRunningApplication, in content: SCShareableContent) -> WindowList {
        WindowProvider.windows(for: app, in: content,
                               includeMinimized: DockPeekSettings.includeMinimized,
                               includeOtherSpaces: DockPeekSettings.includeOtherSpaces)
    }

    /// Shows (or updates) the preview, unless the pointer already left the icon or there is nothing to show.
    private func presentIfStillHovering(_ list: WindowList, app: NSRunningApplication, item: DockItem) -> Bool {
        // Showing the panel after the pointer left would put it under the pointer and keep it open.
        guard isMouseOver(item) || isMouseInsidePanel else {
            Log.app.debug("Pointer left \(item.title, privacy: .public) before its preview was ready")
            hide()
            return false
        }
        let tooFew = list.entries.isEmpty || (DockPeekSettings.skipSingleWindow && list.entries.count == 1)
        guard !tooFew else {
            hide()
            return false
        }
        present(entries: list.entries, app: app, item: item)
        return true
    }

    private func present(entries: [WindowEntry], app: NSRunningApplication, item: DockItem) {
        let orientation = DockOrientation.current
        let screen = NSScreen.screens.first { $0.frame.intersects(item.frame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        model.appName = app.localizedName ?? item.title
        model.appIcon = app.icon
        model.vertical = orientation != .bottom
        switch orientation {
        case .bottom: model.tailEdge = .bottom
        case .left: model.tailEdge = .left
        case .right: model.tailEdge = .right
        }
        model.thumbnailMaxSize = Self.thumbnailSize(count: entries.count, orientation: orientation, visible: visible)
        model.windows = entries.map { entry in
            var entry = entry
            if entry.thumbnail == nil, !entry.isMinimized { entry.thumbnail = thumbnailCache[entry.id] }
            return entry
        }
        shownItem = item

        layoutPanel(anchor: DockGeometry.anchor(for: item.frame), orientation: orientation, visible: visible)
        if !isPresented {
            isPresented = true
            panel.ignoresMouseEvents = false
            // Start partly visible, so it shows up at once (a fade from zero reads as a delay) and only
            // the hard pop is softened.
            if !panel.isVisible || panel.alphaValue < Self.fadeInStartAlpha { panel.alphaValue = Self.fadeInStartAlpha }
            panel.orderFrontRegardless()
            fade(to: 1, duration: Self.fadeInDuration)
        }
        startPolling()
    }

    private func layoutPanel(anchor: CGRect, orientation: DockOrientation, visible: CGRect) {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        // Close to the resting icon (crossing a wide gap made the Dock start hiding). The panel includes the
        // tail, which reaches into the gap towards the icon.
        let inset = Self.gap - PreviewTail.length
        var origin: CGPoint
        switch orientation {
        case .bottom:
            origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + inset)
        case .left:
            origin = CGPoint(x: anchor.maxX + inset, y: anchor.midY - size.height / 2)
        case .right:
            origin = CGPoint(x: anchor.minX - size.width - inset, y: anchor.midY - size.height / 2)
        }
        // Keep it on screen, but ignore the Dock's own edge of the visible frame: that edge moves while the
        // Dock is held (auto-hide off reserves its space) and would push the preview away from the Dock.
        var bounds = visible
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.frame {
            switch orientation {
            case .bottom: bounds = CGRect(x: visible.minX, y: screen.minY, width: visible.width, height: visible.maxY - screen.minY)
            case .left: bounds = CGRect(x: screen.minX, y: visible.minY, width: visible.maxX - screen.minX, height: visible.height)
            case .right: bounds = CGRect(x: visible.minX, y: visible.minY, width: screen.maxX - visible.minX, height: visible.height)
            }
        }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - size.width - 4)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height - 4)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        // Point the tail at the icon even when the preview was pushed sideways to stay on screen.
        switch orientation {
        case .bottom: model.tailPosition = anchor.midX - origin.x
        case .left, .right: model.tailPosition = origin.y + size.height - anchor.midY
        }
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
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
            for entry in entries where !entry.isMinimized {
                guard let window = scWindows[entry.id] else { continue }
                group.addTask { (entry.id, await WindowProvider.thumbnail(for: window, fitting: maxSize, scale: scale)) }
            }
            for await (id, image) in group {
                guard !Task.isCancelled, let image else { continue }
                thumbnailCache[id] = image
                guard let index = model.windows.firstIndex(where: { $0.id == id }) else { continue }
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
            layoutPanel(anchor: DockGeometry.anchor(for: item.frame), orientation: .current, visible: screen?.visibleFrame ?? .zero)
        }
    }

    func hide() {
        DockAutohideLock.release()
        pendingShow?.cancel()
        loadTask?.cancel()
        pollTimer?.invalidate()
        pollTimer = nil
        outsideSince = nil
        shownItem = nil
        if isPresented {
            isPresented = false
            panel.ignoresMouseEvents = true
            fade(to: 0, duration: Self.fadeOutDuration) { [weak self] in
                // A new preview may have started while fading out.
                guard let self, !self.isPresented else { return }
                self.panel.orderOut(nil)
                self.model.windows = []   // after the fade, so the content doesn't vanish mid-fade
            }
        } else {
            model.windows = []
        }
        // Bounded: start over once it holds many windows (closed windows' images go with it).
        if thumbnailCache.count > 60 { thumbnailCache.removeAll() }
    }

    // MARK: - Auto-hide

    private var isMouseInsidePanel: Bool {
        isPresented && panel.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { [weak self] in self?.checkMouse() }
        }
    }

    /// The Dock does not always report that the pointer left an icon (e.g. when it auto-hides or the
    /// pointer leaves quickly), so the AX selection alone can be stale: confirm with the pointer position.
    private func isMouseOver(_ item: DockItem) -> Bool {
        // Up to the magnified icon's full size, which also covers the gap up to the preview.
        var area = DockGeometry.anchor(for: item.frame, magnified: true).insetBy(dx: -6, dy: -6)
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
        // Hold an auto-hiding Dock only while the pointer is in the preview (holding it makes macOS reserve
        // the Dock's space), and let it go as soon as the pointer leaves.
        if isMouseInsidePanel, DockPeekSettings.keepDockVisible {
            DockAutohideLock.hold()
        } else {
            DockAutohideLock.release()
        }
        let hovered = hoveredItem.flatMap { isMouseOver($0) ? $0 : nil }
        // Over the shown icon counts even if the Dock dropped its hover state (it can when the Dock auto-hides).
        let overShownIcon = shownItem.map(isMouseOver) ?? false
        if isMouseInsidePanel || overShownIcon {
            outsideSince = nil
            return
        }
        // A different Dock icon is hovered: its own show() will replace the content.
        if hovered != nil, hovered != suppressedItem { outsideSince = nil; return }
        let since = outsideSince ?? Date()
        outsideSince = since
        var delay = Double(DockPeekSettings.hideDelayMs) / 1000
        // Moving between icons, the Dock briefly reports no icon: on the Dock itself, don't close the
        // preview just to reopen it for the next icon a moment later.
        if isMouseOverDock { delay = max(delay, Self.dockGrace) }
        if Date().timeIntervalSince(since) >= delay { hide() }
    }

    private static let dockGrace: TimeInterval = 0.35

    /// The strip of screen the Dock occupies (up to the magnified icon height), next to the shown icon's screen edge.
    private var isMouseOverDock: Bool {
        guard let item = shownItem,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(item.frame) })?.frame
        else { return false }
        let anchor = DockGeometry.anchor(for: item.frame, magnified: true)
        let mouse = NSEvent.mouseLocation
        guard screen.contains(mouse) else { return false }
        switch DockOrientation.current {
        case .bottom: return mouse.y <= anchor.maxY
        case .left: return mouse.x <= anchor.maxX
        case .right: return mouse.x >= anchor.minX
        }
    }
}
