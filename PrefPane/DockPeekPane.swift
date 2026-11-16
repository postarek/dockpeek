import AppKit
import PreferencePanes

/// System Settings pane for DockPeek (loaded by the legacy pane loader, outside the app process).
/// DockPeekSettings.swift is compiled into this bundle by build.sh.
@objc(DockPeekPane)
final class DockPeekPane: NSPreferencePane {
    private let appBundleID = DockPeekSettings.domain

    private let statusLabel = NSTextField(labelWithString: "")
    private let statusDot = NSImageView()
    private let launchButton = NSButton(title: "Open DockPeek", target: nil, action: nil)

    private let enabledCheckbox = NSButton(checkboxWithTitle: "Enable window previews", target: nil, action: nil)
    private let delayField = NSTextField()
    private let delayStepper = NSStepper()
    private let hideDelayField = NSTextField()
    private let hideDelayStepper = NSStepper()
    private let sizePopup = NSPopUpButton()
    private let otherSpacesCheckbox = NSButton(checkboxWithTitle: "Windows from other Spaces", target: nil, action: nil)
    private let minimizedCheckbox = NSButton(checkboxWithTitle: "Minimized and hidden windows", target: nil, action: nil)
    private let hideOnClickCheckbox = NSButton(checkboxWithTitle: "Hide when a Dock item is clicked", target: nil, action: nil)
    private let skipSingleCheckbox = NSButton(checkboxWithTitle: "Don't show if the app has only one window", target: nil, action: nil)
    private let keepDockCheckbox = NSButton(checkboxWithTitle: "Keep the Dock visible while a preview is open", target: nil, action: nil)
    private let autoUpdateCheckbox = NSButton(checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)
    private let checkNowButton = NSButton(title: "Check Now", target: nil, action: nil)

    private var dependentControls: [NSControl] {
        [delayField, delayStepper, hideDelayField, hideDelayStepper, sizePopup, otherSpacesCheckbox, minimizedCheckbox, hideOnClickCheckbox, skipSingleCheckbox, keepDockCheckbox]
    }

    private var statusTimer: Timer?

    // MARK: - Lifecycle

    override func loadMainView() -> NSView {
        let view = buildView()
        mainView = view
        mainViewDidLoad()
        return view
    }

    override func mainViewDidLoad() {
        loadValues()
    }

    override func didSelect() {
        loadValues()
        refreshStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    override func willUnselect() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    // MARK: - Layout

    private func buildView() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 668, height: 520))

        // Status header
        statusDot.imageScaling = .scaleProportionallyUpOrDown
        statusDot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 10).isActive = true
        launchButton.target = self
        launchButton.action = #selector(launchApp)
        launchButton.bezelStyle = .rounded
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.textColor = .secondaryLabelColor
        let statusRow = NSStackView(views: [statusDot, statusLabel, NSView(), versionLabel, launchButton])
        statusRow.spacing = 8

        // Main toggle
        enabledCheckbox.target = self
        enabledCheckbox.action = #selector(enabledChanged)
        let enabledRow = NSStackView(views: [enabledCheckbox])
        enabledRow.alignment = .centerX

        // Activation and hide delays
        let delayRow = makeDelayRow(field: delayField, stepper: delayStepper,
                                    fieldAction: #selector(delayFieldChanged), stepperAction: #selector(delayStepperChanged))
        let hideDelayRow = makeDelayRow(field: hideDelayField, stepper: hideDelayStepper,
                                        fieldAction: #selector(hideDelayFieldChanged), stepperAction: #selector(hideDelayStepperChanged))

        // Preview size
        sizePopup.addItems(withTitles: DockPeekSettings.PreviewSize.allCases.map(\.title))
        sizePopup.target = self
        sizePopup.action = #selector(sizeChanged)

        checkNowButton.target = self
        checkNowButton.action = #selector(checkForUpdates)
        checkNowButton.bezelStyle = .rounded
        checkNowButton.controlSize = .small
        let updatesRow = NSStackView(views: [autoUpdateCheckbox, checkNowButton])
        updatesRow.spacing = 12

        for checkbox in [otherSpacesCheckbox, minimizedCheckbox, hideOnClickCheckbox, skipSingleCheckbox, keepDockCheckbox, autoUpdateCheckbox] {
            checkbox.target = self
            checkbox.action = #selector(checkboxChanged(_:))
        }

        let grid = NSGridView(views: [
            [label("Activation delay:"), delayRow],
            [label("Hide delay:"), hideDelayRow],
            [label("Preview size:"), sizePopup],
            [label("Include:"), otherSpacesCheckbox],
            [NSGridCell.emptyContentView, minimizedCheckbox],
            [label("Behavior:"), hideOnClickCheckbox],
            [NSGridCell.emptyContentView, skipSingleCheckbox],
            [NSGridCell.emptyContentView, keepDockCheckbox],
            [label("Updates:"), updatesRow],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 8
        grid.rowSpacing = 10
        grid.row(at: 3).topPadding = 8
        grid.row(at: 5).topPadding = 8
        grid.row(at: 8).topPadding = 8

        let separator = NSBox()
        separator.boxType = .separator

        let gridWrapper = NSStackView(views: [grid])
        gridWrapper.alignment = .centerX

        let content = NSStackView(views: [statusRow, makeSeparator(), enabledRow, separator, gridWrapper, NSView()])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 16, right: 24)
        content.translatesAutoresizingMaskIntoConstraints = false
        for row in [statusRow, enabledRow, separator, gridWrapper] {
            row.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48).isActive = true
        }

        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        return root
    }

    private func makeDelayRow(field: NSTextField, stepper: NSStepper, fieldAction: Selector, stepperAction: Selector) -> NSView {
        field.alignment = .right
        field.formatter = {
            let formatter = NumberFormatter()
            formatter.minimum = NSNumber(value: DockPeekSettings.activationDelayRange.lowerBound)
            formatter.maximum = NSNumber(value: DockPeekSettings.activationDelayRange.upperBound)
            formatter.allowsFloats = false
            return formatter
        }()
        field.widthAnchor.constraint(equalToConstant: 60).isActive = true
        field.target = self
        field.action = fieldAction
        stepper.minValue = Double(DockPeekSettings.activationDelayRange.lowerBound)
        stepper.maxValue = Double(DockPeekSettings.activationDelayRange.upperBound)
        stepper.increment = 10
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = stepperAction
        let row = NSStackView(views: [field, stepper, NSTextField(labelWithString: "ms")])
        row.spacing = 4
        return row
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private var version: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    // MARK: - Values

    private func loadValues() {
        DockPeekSettings.store.synchronize()
        enabledCheckbox.state = DockPeekSettings.previewsEnabled ? .on : .off
        delayField.integerValue = DockPeekSettings.activationDelayMs
        delayStepper.integerValue = DockPeekSettings.activationDelayMs
        hideDelayField.integerValue = DockPeekSettings.hideDelayMs
        hideDelayStepper.integerValue = DockPeekSettings.hideDelayMs
        sizePopup.selectItem(at: DockPeekSettings.previewSize.rawValue)
        otherSpacesCheckbox.state = DockPeekSettings.includeOtherSpaces ? .on : .off
        minimizedCheckbox.state = DockPeekSettings.includeMinimized ? .on : .off
        hideOnClickCheckbox.state = DockPeekSettings.hideOnDockClick ? .on : .off
        skipSingleCheckbox.state = DockPeekSettings.skipSingleWindow ? .on : .off
        autoUpdateCheckbox.state = DockPeekSettings.autoCheckUpdates ? .on : .off
        keepDockCheckbox.state = DockPeekSettings.keepDockVisible ? .on : .off
        updateEnabledState()
    }

    private func updateEnabledState() {
        let enabled = enabledCheckbox.state == .on
        dependentControls.forEach { $0.isEnabled = enabled }
    }

    private func refreshStatus() {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).isEmpty
        statusLabel.stringValue = running ? "DockPeek is running." : "DockPeek is not running."
        let symbol = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [running ? .systemGreen : .systemGray]))
        statusDot.image = symbol
        launchButton.isHidden = running
        checkNowButton.isEnabled = running
    }

    // MARK: - Actions

    @objc private func enabledChanged() {
        DockPeekSettings.previewsEnabled = enabledCheckbox.state == .on
        updateEnabledState()
    }

    @objc private func delayFieldChanged() {
        DockPeekSettings.activationDelayMs = delayField.integerValue
        delayStepper.integerValue = DockPeekSettings.activationDelayMs
        delayField.integerValue = DockPeekSettings.activationDelayMs
    }

    @objc private func delayStepperChanged() {
        DockPeekSettings.activationDelayMs = delayStepper.integerValue
        delayField.integerValue = DockPeekSettings.activationDelayMs
    }

    @objc private func hideDelayFieldChanged() {
        DockPeekSettings.hideDelayMs = hideDelayField.integerValue
        hideDelayStepper.integerValue = DockPeekSettings.hideDelayMs
        hideDelayField.integerValue = DockPeekSettings.hideDelayMs
    }

    @objc private func hideDelayStepperChanged() {
        DockPeekSettings.hideDelayMs = hideDelayStepper.integerValue
        hideDelayField.integerValue = DockPeekSettings.hideDelayMs
    }

    @objc private func sizeChanged() {
        DockPeekSettings.previewSize = DockPeekSettings.PreviewSize(rawValue: sizePopup.indexOfSelectedItem) ?? .medium
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender {
        case otherSpacesCheckbox: DockPeekSettings.includeOtherSpaces = on
        case minimizedCheckbox: DockPeekSettings.includeMinimized = on
        case hideOnClickCheckbox: DockPeekSettings.hideOnDockClick = on
        case skipSingleCheckbox: DockPeekSettings.skipSingleWindow = on
        case autoUpdateCheckbox: DockPeekSettings.autoCheckUpdates = on
        case keepDockCheckbox: DockPeekSettings.keepDockVisible = on
        default: break
        }
    }

    /// The check runs in the app (it is the one that gets replaced).
    @objc private func checkForUpdates() {
        DistributedNotificationCenter.default().postNotificationName(
            DockPeekSettings.checkForUpdatesNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    @objc private func launchApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refreshStatus() }
        }
    }
}
