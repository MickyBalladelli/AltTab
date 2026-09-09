import AppKit

final class AppProfilesWindowController: NSWindowController {
    static let shared = AppProfilesWindowController()

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 390), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "App Profiles"
        window.center()
        self.init(window: window)
        window.contentView = AppProfilesView(frame: window.contentView!.bounds)
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        (window?.contentView as? AppProfilesView)?.refresh()
    }
}

final class AppProfilesView: NSView {
    private let bundleField = NSTextField(string: "")
    private let profilesPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let summaryLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildControls()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildControls()
    }

    private func buildControls() {
        autoresizingMask = [.width, .height]

        let title = NSTextField(labelWithString: "Per-app profiles")
        title.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        title.frame = NSRect(x: 28, y: bounds.height - 52, width: bounds.width - 56, height: 30)
        title.autoresizingMask = [.width, .minYMargin]
        addSubview(title)

        let subtitle = NSTextField(labelWithString: "Save content, filter, and appearance settings for one app.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 30, y: bounds.height - 78, width: bounds.width - 60, height: 18)
        subtitle.autoresizingMask = [.width, .minYMargin]
        addSubview(subtitle)

        let bundleLabel = NSTextField(labelWithString: "Bundle ID")
        bundleLabel.frame = NSRect(x: 30, y: bounds.height - 124, width: 100, height: 20)
        bundleLabel.autoresizingMask = [.minYMargin]
        addSubview(bundleLabel)

        bundleField.placeholderString = "com.example.App"
        bundleField.frame = NSRect(x: 140, y: bounds.height - 128, width: 310, height: 26)
        bundleField.autoresizingMask = [.width, .minYMargin]
        addSubview(bundleField)

        let frontmostButton = NSButton(title: "Use frontmost", target: self, action: #selector(useFrontmostApp))
        frontmostButton.bezelStyle = .rounded
        frontmostButton.frame = NSRect(x: 460, y: bounds.height - 128, width: 130, height: 26)
        frontmostButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(frontmostButton)

        let profileLabel = NSTextField(labelWithString: "Saved profiles")
        profileLabel.frame = NSRect(x: 30, y: bounds.height - 174, width: 100, height: 20)
        profileLabel.autoresizingMask = [.minYMargin]
        addSubview(profileLabel)

        profilesPopup.target = self
        profilesPopup.action = #selector(selectProfile(_:))
        profilesPopup.frame = NSRect(x: 140, y: bounds.height - 178, width: 450, height: 26)
        profilesPopup.autoresizingMask = [.width, .minYMargin]
        addSubview(profilesPopup)

        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.maximumNumberOfLines = 0
        summaryLabel.frame = NSRect(x: 30, y: 98, width: bounds.width - 60, height: 58)
        summaryLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(summaryLabel)

        let saveButton = NSButton(title: "Save current settings", target: self, action: #selector(saveProfile))
        saveButton.bezelStyle = .rounded
        saveButton.frame = NSRect(x: 30, y: 48, width: 170, height: 28)
        saveButton.autoresizingMask = [.minYMargin]
        addSubview(saveButton)

        let deleteButton = NSButton(title: "Delete profile", target: self, action: #selector(deleteProfile))
        deleteButton.bezelStyle = .rounded
        deleteButton.frame = NSRect(x: 212, y: 48, width: 130, height: 28)
        deleteButton.autoresizingMask = [.minYMargin]
        addSubview(deleteButton)

        refresh()
    }

    func refresh() {
        profilesPopup.removeAllItems()
        profilesPopup.addItem(withTitle: "No saved profile selected")
        profilesPopup.item(at: 0)?.isEnabled = false
        for bundleIdentifier in AppProfileStore.bundleIdentifiers {
            profilesPopup.addItem(withTitle: bundleIdentifier)
            profilesPopup.item(at: profilesPopup.numberOfItems - 1)?.representedObject = bundleIdentifier
        }
        updateSummary()
    }

    @objc private func useFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              let bundleIdentifier = app.bundleIdentifier else {
            showError("No other frontmost app found.")
            return
        }
        bundleField.stringValue = bundleIdentifier
        updateSummary()
    }

    @objc private func selectProfile(_ sender: NSPopUpButton) {
        guard let bundleIdentifier = sender.selectedItem?.representedObject as? String else { return }
        bundleField.stringValue = bundleIdentifier
        updateSummary()
    }

    @objc private func saveProfile() {
        let bundleIdentifier = bundleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty else {
            showError("Enter an app bundle ID first.")
            return
        }
        AppProfileStore.save(SettingsStore.profileSnapshot(), for: bundleIdentifier)
        refresh()
        profilesPopup.selectItem(withTitle: bundleIdentifier)
        updateSummary()
    }

    @objc private func deleteProfile() {
        let bundleIdentifier = bundleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty, AppProfileStore.profile(for: bundleIdentifier) != nil else { return }
        AppProfileStore.removeProfile(for: bundleIdentifier)
        refresh()
        bundleField.stringValue = ""
    }

    private func updateSummary() {
        let bundleIdentifier = bundleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile = AppProfileStore.profile(for: bundleIdentifier) else {
            summaryLabel.stringValue = "No saved profile for this bundle ID. Save the current global settings to create one."
            return
        }
        summaryLabel.stringValue = "Saved: \(profile.resolvedContentMode.title), \(profile.excludedBundleIdentifiers.count) excluded apps, \(profile.columns) columns, thumbnail \(Int(profile.thumbnailSize)) pt."
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "App profile"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
