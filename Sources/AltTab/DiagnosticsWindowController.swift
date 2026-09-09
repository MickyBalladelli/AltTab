import AppKit

final class DiagnosticsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = DiagnosticsWindowController()
    private let focusRestorer = WindowFocusRestorer()

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 520), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AltTab Diagnostics & Permissions"
        window.center()
        self.init(window: window)
        window.delegate = self
        window.contentView = DiagnosticsView(frame: window.contentView!.bounds)
    }

    override func showWindow(_ sender: Any?) {
        focusRestorer.capture()
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        if let contentView = window?.contentView as? DiagnosticsView {
            window?.recalculateKeyViewLoop()
            window?.makeFirstResponder(contentView.initialFirstResponder)
        }
        (window?.contentView as? DiagnosticsView)?.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        focusRestorer.restore()
    }
}

final class DiagnosticsView: NSView {
    private let detailsLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "Open Accessibility Settings", target: nil, action: nil)

    var initialFirstResponder: NSView { permissionButton }

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

        let title = NSTextField(labelWithString: "Local status only")
        title.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        title.frame = NSRect(x: 28, y: bounds.height - 58, width: bounds.width - 56, height: 32)
        title.autoresizingMask = [.width, .minYMargin]
        addSubview(title)

        let subtitle = NSTextField(labelWithString: "AltTab sends no telemetry. This page reads local settings and macOS status.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 30, y: bounds.height - 88, width: bounds.width - 60, height: 20)
        subtitle.autoresizingMask = [.width, .minYMargin]
        addSubview(subtitle)

        detailsLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        detailsLabel.maximumNumberOfLines = 0
        detailsLabel.lineBreakMode = .byWordWrapping
        detailsLabel.frame = NSRect(x: 30, y: 106, width: bounds.width - 60, height: bounds.height - 220)
        detailsLabel.autoresizingMask = [.width, .height]
        addSubview(detailsLabel)

        permissionButton.target = self
        permissionButton.action = #selector(openAccessibilitySettings)
        permissionButton.bezelStyle = .rounded
        permissionButton.frame = NSRect(x: 30, y: 58, width: 190, height: 28)
        permissionButton.autoresizingMask = [.minYMargin]
        addSubview(permissionButton)

        let copyButton = NSButton(title: "Copy diagnostics", target: self, action: #selector(copyDiagnostics))
        copyButton.bezelStyle = .rounded
        copyButton.frame = NSRect(x: 232, y: 58, width: 150, height: 28)
        copyButton.autoresizingMask = [.minYMargin]
        addSubview(copyButton)

        refresh()
    }

    func refresh() {
        detailsLabel.stringValue = "Loading local diagnostics..."
        WindowCatalog.loadItems(for: .windows) { [weak self] loadedItems in
            self?.render(windowCount: loadedItems.count)
        }
    }

    private func render(windowCount: Int) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let profile = WindowCatalog.lastProfile
        detailsLabel.stringValue = """
        Version:                 \(version) (build \(build))
        macOS:                  \(ProcessInfo.processInfo.operatingSystemVersionString)
        Accessibility:          \(AccessibilityController.isTrusted ? "Granted" : "Needed")
        VoiceOver:              \(SystemAccessibility.voiceOverEnabled ? "On" : "Off")
        Reduce Motion:          \(SystemAccessibility.reduceMotion ? "On" : "Off")
        Increase Contrast:      \(SystemAccessibility.increaseContrast ? "On" : "Off")
        Reduce Transparency:    \(SystemAccessibility.reduceTransparency ? "On" : "Off")
        Content mode:           \(SettingsStore.contentMode.title)
        Windows currently seen: \(windowCount)
        Enumeration time:       \(String(format: "%.1f ms", profile.elapsedMilliseconds))
        Icon cache:              \(profile.iconCacheHits) hits, \(profile.iconCacheMisses) misses
        Thumbnail cache:         \(profile.thumbnailCacheHits) hits, \(profile.thumbnailCacheMisses) misses
        Saved MRU entries:      \(MRUStore.savedIdentifiers.count)
        """
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityController.openSystemSettings()
    }

    @objc private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(detailsLabel.stringValue, forType: .string)
    }
}
