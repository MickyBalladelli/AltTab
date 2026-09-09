import AppKit
import ServiceManagement

enum LaunchAtLoginStore {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

final class WorkflowSettingsWindowController: NSWindowController {
    static let shared = WorkflowSettingsWindowController()

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 230), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Workflow Settings"
        window.center()
        self.init(window: window)
        window.contentView = WorkflowSettingsView(frame: window.contentView!.bounds)
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class WorkflowSettingsView: NSView {
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch AltTab at login", target: nil, action: nil)
    private let rememberLastModeCheckbox = NSButton(checkboxWithTitle: "Remember last switcher mode", target: nil, action: nil)
    private let modeLabel = NSTextField(labelWithString: "Current mode: ")

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

        let title = NSTextField(labelWithString: "Workflow")
        title.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        title.frame = NSRect(x: 26, y: bounds.height - 48, width: bounds.width - 52, height: 30)
        title.autoresizingMask = [.width, .minYMargin]
        addSubview(title)

        let subtitle = NSTextField(labelWithString: "Choose what AltTab remembers and when it starts.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 28, y: bounds.height - 74, width: bounds.width - 56, height: 18)
        subtitle.autoresizingMask = [.width, .minYMargin]
        addSubview(subtitle)

        launchAtLoginCheckbox.state = LaunchAtLoginStore.isEnabled ? .on : .off
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        launchAtLoginCheckbox.frame = NSRect(x: 28, y: 112, width: bounds.width - 56, height: 24)
        launchAtLoginCheckbox.autoresizingMask = [.width, .minYMargin]
        addSubview(launchAtLoginCheckbox)

        rememberLastModeCheckbox.state = SettingsStore.rememberLastMode ? .on : .off
        rememberLastModeCheckbox.target = self
        rememberLastModeCheckbox.action = #selector(toggleRememberLastMode)
        rememberLastModeCheckbox.frame = NSRect(x: 28, y: 76, width: bounds.width - 56, height: 24)
        rememberLastModeCheckbox.autoresizingMask = [.width, .minYMargin]
        addSubview(rememberLastModeCheckbox)

        modeLabel.stringValue = "Current mode: \(SettingsStore.modeForNextSwitcher.title)"
        modeLabel.textColor = .secondaryLabelColor
        modeLabel.frame = NSRect(x: 28, y: 40, width: bounds.width - 56, height: 20)
        modeLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(modeLabel)
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = launchAtLoginCheckbox.state == .on
        do {
            try LaunchAtLoginStore.setEnabled(enabled)
        } catch {
            launchAtLoginCheckbox.state = enabled ? .off : .on
            showError("macOS could not change Launch at login. Use a bundled AltTab app, then try again.")
        }
    }

    @objc private func toggleRememberLastMode() {
        SettingsStore.rememberLastMode = rememberLastModeCheckbox.state == .on
        modeLabel.stringValue = "Current mode: \(SettingsStore.modeForNextSwitcher.title)"
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Workflow setting not changed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
