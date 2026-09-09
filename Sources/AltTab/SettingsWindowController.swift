import AppKit

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
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
    private let utilityWindowsCheckbox = NSButton(checkboxWithTitle: "Show utility windows", target: nil, action: nil)
    private let minimizedWindowsCheckbox = NSButton(checkboxWithTitle: "Show minimized windows", target: nil, action: nil)
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
        title.frame = NSRect(x: 32, y: bounds.height - 62, width: bounds.width - 64, height: 32)
        title.autoresizingMask = [.width, .minYMargin]
        addSubview(title)

        let subtitle = makeLabel("Choose what appears in the switcher. Changes save immediately.", size: 13, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 34, y: bounds.height - 92, width: bounds.width - 68, height: 20)
        subtitle.autoresizingMask = [.width, .minYMargin]
        addSubview(subtitle)

        let shortcutLabel = makeLabel("Switcher shortcut", size: 13, weight: .medium)
        shortcutLabel.frame = NSRect(x: 34, y: bounds.height - 140, width: 190, height: 20)
        shortcutLabel.autoresizingMask = [.minYMargin]
        addSubview(shortcutLabel)

        let shortcutValue = makeLabel("Option + Tab", size: 13, weight: .regular)
        shortcutValue.alignment = .right
        shortcutValue.textColor = .secondaryLabelColor
        shortcutValue.frame = NSRect(x: bounds.width - 210, y: bounds.height - 140, width: 176, height: 20)
        shortcutValue.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(shortcutValue)

        utilityWindowsCheckbox.state = SettingsStore.showUtilityWindows ? .on : .off
        utilityWindowsCheckbox.target = self
        utilityWindowsCheckbox.action = #selector(toggleUtilityWindows)
        utilityWindowsCheckbox.frame = NSRect(x: 32, y: bounds.height - 192, width: bounds.width - 64, height: 24)
        utilityWindowsCheckbox.autoresizingMask = [.width, .minYMargin]
        addSubview(utilityWindowsCheckbox)

        minimizedWindowsCheckbox.state = SettingsStore.showMinimizedWindows ? .on : .off
        minimizedWindowsCheckbox.target = self
        minimizedWindowsCheckbox.action = #selector(toggleMinimizedWindows)
        minimizedWindowsCheckbox.frame = NSRect(x: 32, y: bounds.height - 228, width: bounds.width - 64, height: 24)
        minimizedWindowsCheckbox.autoresizingMask = [.width, .minYMargin]
        addSubview(minimizedWindowsCheckbox)

        let excludedLabel = makeLabel("Excluded app bundle IDs", size: 13, weight: .medium)
        excludedLabel.frame = NSRect(x: 34, y: bounds.height - 278, width: bounds.width - 68, height: 20)
        excludedLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(excludedLabel)

        excludedAppsField.placeholderString = "com.apple.dock, com.example.App"
        excludedAppsField.stringValue = SettingsStore.excludedBundleIdentifiers.sorted().joined(separator: ", ")
        excludedAppsField.frame = NSRect(x: 32, y: bounds.height - 316, width: bounds.width - 142, height: 26)
        excludedAppsField.autoresizingMask = [.width, .minYMargin]
        addSubview(excludedAppsField)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveExcludedApps))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: bounds.width - 96, y: bounds.height - 316, width: 64, height: 26)
        saveButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(saveButton)

        let permissionLabel = makeLabel("Accessibility", size: 13, weight: .medium)
        permissionLabel.frame = NSRect(x: 34, y: bounds.height - 362, width: 130, height: 20)
        permissionLabel.autoresizingMask = [.minYMargin]
        addSubview(permissionLabel)

        permissionStatusLabel.alignment = .right
        permissionStatusLabel.frame = NSRect(x: 170, y: bounds.height - 362, width: 150, height: 20)
        permissionStatusLabel.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(permissionStatusLabel)
        refreshPermissionStatus()

        let permissionButton = NSButton(title: "Open System Settings", target: self, action: #selector(openAccessibilitySettings))
        permissionButton.bezelStyle = .rounded
        permissionButton.frame = NSRect(x: bounds.width - 210, y: bounds.height - 365, width: 176, height: 26)
        permissionButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(permissionButton)

        let tip = makeLabel("Tip: use commas to exclude more than one app. Settings live in UserDefaults.", size: 11, weight: .regular)
        tip.textColor = .tertiaryLabelColor
        tip.frame = NSRect(x: 34, y: 24, width: bounds.width - 68, height: 18)
        tip.autoresizingMask = [.width, .maxYMargin]
        addSubview(tip)
    }

    @objc private func toggleUtilityWindows() {
        SettingsStore.showUtilityWindows = utilityWindowsCheckbox.state == .on
    }

    @objc private func toggleMinimizedWindows() {
        SettingsStore.showMinimizedWindows = minimizedWindowsCheckbox.state == .on
    }

    @objc private func saveExcludedApps() {
        SettingsStore.setExcludedBundleIdentifiers(excludedAppsField.stringValue)
        excludedAppsField.stringValue = SettingsStore.excludedBundleIdentifiers.sorted().joined(separator: ", ")
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityController.openSystemSettings()
        DispatchQueue.main.async { [weak self] in
            self?.refreshPermissionStatus()
        }
    }

    private func refreshPermissionStatus() {
        permissionStatusLabel.stringValue = AccessibilityController.isTrusted ? "Granted" : "Needed"
        permissionStatusLabel.textColor = AccessibilityController.isTrusted ? .systemGreen : .systemOrange
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        return label
    }
}
