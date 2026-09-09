import AppKit

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 840), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AltTab Settings"
        window.center()
        self.init(window: window)
        window.contentView = SettingsView(frame: window.contentView!.bounds)
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class SettingsView: NSView {
    private let contentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let columnsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let accentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let shortcutPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let thumbnailSlider = NSSlider()
    private let iconSlider = NSSlider()
    private let cornerSlider = NSSlider()
    private let opacitySlider = NSSlider()
    private let thumbnailValue = NSTextField(labelWithString: "")
    private let iconValue = NSTextField(labelWithString: "")
    private let cornerValue = NSTextField(labelWithString: "")
    private let opacityValue = NSTextField(labelWithString: "")
    private let labelsCheckbox = NSButton(checkboxWithTitle: "Show labels", target: nil, action: nil)
    private let blurCheckbox = NSButton(checkboxWithTitle: "Background blur", target: nil, action: nil)
    private let currentDisplayCheckbox = NSButton(checkboxWithTitle: "Show only windows on this display", target: nil, action: nil)
    private let utilityWindowsCheckbox = NSButton(checkboxWithTitle: "Show utility windows", target: nil, action: nil)
    private let minimizedWindowsCheckbox = NSButton(checkboxWithTitle: "Show minimized windows", target: nil, action: nil)
    private let holdToPreviewCheckbox = NSButton(checkboxWithTitle: "Hold activation key to preview, release to switch", target: nil, action: nil)
    private let excludedAppsField = NSTextField(string: "")
    private let permissionStatusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildControls()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildControls()
    }

    private func buildControls() {
        SettingsStore.registerDefaults()
        autoresizingMask = [.width, .height]

        let title = makeLabel("Make switching feel like yours.", size: 24, weight: .bold)
        title.frame = NSRect(x: 32, y: bounds.height - 58, width: bounds.width - 64, height: 32)
        title.autoresizingMask = [.width, .minYMargin]
        addSubview(title)

        let subtitle = makeLabel("Choose the content, appearance, filters, and shortcut behavior. Changes save immediately.", size: 13, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 34, y: bounds.height - 88, width: bounds.width - 68, height: 20)
        subtitle.autoresizingMask = [.width, .minYMargin]
        addSubview(subtitle)

        addSectionTitle("Switcher contents", y: bounds.height - 132)
        configureContentPopup()
        addRow(label: "Show", y: bounds.height - 164, control: contentPopup)

        addSectionTitle("Appearance", y: bounds.height - 210)
        configureSlider(thumbnailSlider, value: SettingsStore.thumbnailSize, min: 24, max: 96, tag: 1)
        configureSlider(iconSlider, value: SettingsStore.iconSize, min: 20, max: 80, tag: 2)
        configureSlider(cornerSlider, value: SettingsStore.cornerRadius, min: 0, max: 32, tag: 3)
        configureSlider(opacitySlider, value: SettingsStore.opacity, min: 0.4, max: 1, tag: 4)
        addSliderRow(label: "Thumbnail size", y: bounds.height - 246, slider: thumbnailSlider, valueLabel: thumbnailValue)
        addSliderRow(label: "Icon size", y: bounds.height - 286, slider: iconSlider, valueLabel: iconValue)
        addSliderRow(label: "Corner radius", y: bounds.height - 326, slider: cornerSlider, valueLabel: cornerValue)
        addSliderRow(label: "Opacity", y: bounds.height - 366, slider: opacitySlider, valueLabel: opacityValue)

        labelsCheckbox.state = SettingsStore.showLabels ? .on : .off
        labelsCheckbox.target = self
        labelsCheckbox.action = #selector(toggleLabels)
        labelsCheckbox.frame = NSRect(x: 32, y: bounds.height - 408, width: 190, height: 24)
        labelsCheckbox.autoresizingMask = [.minYMargin]
        addSubview(labelsCheckbox)

        blurCheckbox.state = SettingsStore.backgroundBlur ? .on : .off
        blurCheckbox.target = self
        blurCheckbox.action = #selector(toggleBlur)
        blurCheckbox.frame = NSRect(x: 230, y: bounds.height - 408, width: 190, height: 24)
        blurCheckbox.autoresizingMask = [.minYMargin]
        addSubview(blurCheckbox)

        configureColumnsPopup()
        addRow(label: "Columns", y: bounds.height - 448, control: columnsPopup)

        configureAccentPopup()
        addRow(label: "Accent color", y: bounds.height - 488, control: accentPopup)

        currentDisplayCheckbox.state = SettingsStore.onlyCurrentDisplay ? .on : .off
        currentDisplayCheckbox.target = self
        currentDisplayCheckbox.action = #selector(toggleCurrentDisplay)
        currentDisplayCheckbox.frame = NSRect(x: 32, y: bounds.height - 528, width: bounds.width - 64, height: 24)
        currentDisplayCheckbox.autoresizingMask = [.width, .minYMargin]
        addSubview(currentDisplayCheckbox)

        addSectionTitle("Filters", y: bounds.height - 568)
        utilityWindowsCheckbox.state = SettingsStore.showUtilityWindows ? .on : .off
        utilityWindowsCheckbox.target = self
        utilityWindowsCheckbox.action = #selector(toggleUtilityWindows)
        utilityWindowsCheckbox.frame = NSRect(x: 32, y: bounds.height - 600, width: 220, height: 24)
        utilityWindowsCheckbox.autoresizingMask = [.minYMargin]
        addSubview(utilityWindowsCheckbox)

        minimizedWindowsCheckbox.state = SettingsStore.showMinimizedWindows ? .on : .off
        minimizedWindowsCheckbox.target = self
        minimizedWindowsCheckbox.action = #selector(toggleMinimizedWindows)
        minimizedWindowsCheckbox.frame = NSRect(x: 270, y: bounds.height - 636, width: 230, height: 24)
        minimizedWindowsCheckbox.autoresizingMask = [.minYMargin]
        addSubview(minimizedWindowsCheckbox)

        let excludedLabel = makeLabel("Excluded app bundle IDs", size: 13, weight: .medium)
        excludedLabel.frame = NSRect(x: 34, y: bounds.height - 680, width: bounds.width - 68, height: 20)
        excludedLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(excludedLabel)

        excludedAppsField.placeholderString = "com.apple.dock, com.example.App"
        excludedAppsField.stringValue = SettingsStore.excludedBundleIdentifiers.sorted().joined(separator: ", ")
        excludedAppsField.frame = NSRect(x: 32, y: bounds.height - 718, width: bounds.width - 142, height: 26)
        excludedAppsField.autoresizingMask = [.width, .minYMargin]
        addSubview(excludedAppsField)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveExcludedApps))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: bounds.width - 96, y: bounds.height - 718, width: 64, height: 26)
        saveButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(saveButton)

        addSectionTitle("Shortcut", y: bounds.height - 760)
        configureShortcutPopup()
        addRow(label: "Activation", y: bounds.height - 792, control: shortcutPopup)

        holdToPreviewCheckbox.state = SettingsStore.holdToPreview ? .on : .off
        holdToPreviewCheckbox.target = self
        holdToPreviewCheckbox.action = #selector(toggleHoldToPreview)
        holdToPreviewCheckbox.frame = NSRect(x: 32, y: 14, width: 300, height: 24)
        holdToPreviewCheckbox.autoresizingMask = [.minYMargin]
        addSubview(holdToPreviewCheckbox)

        let slotsButton = NSButton(title: "Configure F1-F12...", target: self, action: #selector(showQuickSlots))
        slotsButton.bezelStyle = .rounded
        slotsButton.frame = NSRect(x: 230, y: bounds.height - 792, width: 176, height: 28)
        slotsButton.autoresizingMask = [.minYMargin]
        addSubview(slotsButton)

        permissionStatusLabel.alignment = .right
        permissionStatusLabel.frame = NSRect(x: 340, y: 18, width: 180, height: 20)
        permissionStatusLabel.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(permissionStatusLabel)
        refreshPermissionStatus()

        let permissionButton = NSButton(title: "Accessibility Settings", target: self, action: #selector(openAccessibilitySettings))
        permissionButton.bezelStyle = .rounded
        permissionButton.frame = NSRect(x: bounds.width - 170, y: 14, width: 156, height: 28)
        permissionButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(permissionButton)

        updateValueLabels()
    }

    private func configureContentPopup() {
        for mode in SwitcherContentMode.allCases {
            contentPopup.addItem(withTitle: mode.title)
            contentPopup.item(at: contentPopup.numberOfItems - 1)?.representedObject = mode.rawValue
        }
        contentPopup.selectItem(withTitle: SettingsStore.contentMode.title)
        contentPopup.target = self
        contentPopup.action = #selector(changeContentMode(_:))
    }

    private func configureColumnsPopup() {
        for columns in 1...10 {
            columnsPopup.addItem(withTitle: "\(columns)")
            columnsPopup.item(at: columnsPopup.numberOfItems - 1)?.tag = columns
        }
        columnsPopup.selectItem(withTag: SettingsStore.columns)
        columnsPopup.target = self
        columnsPopup.action = #selector(changeColumns(_:))
    }

    private func configureAccentPopup() {
        let accents = [("Blue", "#0A84FF"), ("Purple", "#8E44AD"), ("Green", "#20A464"), ("Orange", "#FF9500"), ("Red", "#FF375F")]
        for (title, hex) in accents {
            accentPopup.addItem(withTitle: title)
            accentPopup.item(at: accentPopup.numberOfItems - 1)?.representedObject = hex
        }
        let current = accentPopup.itemArray.first { ($0.representedObject as? String) == SettingsStore.accentColorHex }
        if let current {
            accentPopup.select(current)
        } else {
            accentPopup.selectItem(at: 0)
        }
        accentPopup.target = self
        accentPopup.action = #selector(changeAccent(_:))
    }

    private func configureShortcutPopup() {
        for shortcut in ActivationShortcut.allCases {
            shortcutPopup.addItem(withTitle: shortcut.title)
            shortcutPopup.item(at: shortcutPopup.numberOfItems - 1)?.representedObject = shortcut.rawValue
        }
        shortcutPopup.selectItem(withTitle: SettingsStore.activationShortcut.title)
        shortcutPopup.target = self
        shortcutPopup.action = #selector(changeActivationShortcut(_:))
    }

    private func configureSlider(_ slider: NSSlider, value: Double, min: Double, max: Double, tag: Int) {
        slider.minValue = min
        slider.maxValue = max
        slider.doubleValue = value
        slider.tag = tag
        slider.target = self
        slider.action = #selector(changeSlider(_:))
        slider.isContinuous = true
        slider.autoresizingMask = [.width, .minYMargin]
    }

    private func addSliderRow(label: String, y: CGFloat, slider: NSSlider, valueLabel: NSTextField) {
        let labelView = makeLabel(label, size: 13, weight: .regular)
        labelView.frame = NSRect(x: 34, y: y + 3, width: 150, height: 20)
        labelView.autoresizingMask = [.minYMargin]
        addSubview(labelView)

        slider.frame = NSRect(x: 190, y: y, width: bounds.width - 300, height: 24)
        addSubview(slider)

        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: bounds.width - 94, y: y + 3, width: 60, height: 20)
        valueLabel.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(valueLabel)
    }

    private func addRow(label: String, y: CGFloat, control: NSView) {
        let labelView = makeLabel(label, size: 13, weight: .regular)
        labelView.frame = NSRect(x: 34, y: y + 3, width: 150, height: 20)
        labelView.autoresizingMask = [.minYMargin]
        addSubview(labelView)

        control.frame = NSRect(x: 430, y: y, width: 220, height: 26)
        control.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(control)
    }

    private func addSectionTitle(_ text: String, y: CGFloat) {
        let label = makeLabel(text, size: 13, weight: .bold)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 32, y: y, width: bounds.width - 64, height: 20)
        label.autoresizingMask = [.width, .minYMargin]
        addSubview(label)
    }

    @objc private func changeContentMode(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let mode = SwitcherContentMode(rawValue: rawValue) else { return }
        SettingsStore.contentMode = mode
    }

    @objc private func changeColumns(_ sender: NSPopUpButton) {
        SettingsStore.columns = sender.selectedItem?.tag ?? 5
    }

    @objc private func changeAccent(_ sender: NSPopUpButton) {
        guard let hex = sender.selectedItem?.representedObject as? String else { return }
        SettingsStore.accentColorHex = hex
    }

    @objc private func changeActivationShortcut(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let shortcut = ActivationShortcut(rawValue: rawValue) else { return }
        if let conflict = ShortcutStore.conflict(withActivationShortcut: shortcut) {
            sender.selectItem(withTitle: SettingsStore.activationShortcut.title)
            showError(conflict)
            return
        }
        SettingsStore.activationShortcut = shortcut
    }

    @objc private func changeSlider(_ sender: NSSlider) {
        switch sender.tag {
        case 1: SettingsStore.thumbnailSize = sender.doubleValue
        case 2: SettingsStore.iconSize = sender.doubleValue
        case 3: SettingsStore.cornerRadius = sender.doubleValue
        case 4: SettingsStore.opacity = sender.doubleValue
        default: break
        }
        updateValueLabels()
    }

    @objc private func toggleLabels() { SettingsStore.showLabels = labelsCheckbox.state == .on }
    @objc private func toggleBlur() { SettingsStore.backgroundBlur = blurCheckbox.state == .on }
    @objc private func toggleCurrentDisplay() { SettingsStore.onlyCurrentDisplay = currentDisplayCheckbox.state == .on }
    @objc private func toggleUtilityWindows() { SettingsStore.showUtilityWindows = utilityWindowsCheckbox.state == .on }
    @objc private func toggleMinimizedWindows() { SettingsStore.showMinimizedWindows = minimizedWindowsCheckbox.state == .on }
    @objc private func toggleHoldToPreview() { SettingsStore.holdToPreview = holdToPreviewCheckbox.state == .on }

    @objc private func saveExcludedApps() {
        SettingsStore.setExcludedBundleIdentifiers(excludedAppsField.stringValue)
        excludedAppsField.stringValue = SettingsStore.excludedBundleIdentifiers.sorted().joined(separator: ", ")
    }

    @objc private func showQuickSlots() {
        QuickSlotsWindowController.shared.showWindow(nil)
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityController.openSystemSettings()
        DispatchQueue.main.async { [weak self] in
            self?.refreshPermissionStatus()
        }
    }

    private func updateValueLabels() {
        thumbnailValue.stringValue = "\(Int(thumbnailSlider.doubleValue)) pt"
        iconValue.stringValue = "\(Int(iconSlider.doubleValue)) pt"
        cornerValue.stringValue = "\(Int(cornerSlider.doubleValue)) pt"
        opacityValue.stringValue = "\(Int(opacitySlider.doubleValue * 100))%"
    }

    private func refreshPermissionStatus() {
        permissionStatusLabel.stringValue = AccessibilityController.isTrusted ? "Accessibility: Granted" : "Accessibility: Needed"
        permissionStatusLabel.textColor = AccessibilityController.isTrusted ? .systemGreen : .systemOrange
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Shortcut conflict"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        return label
    }
}
