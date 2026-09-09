import AppKit

final class WindowActionShortcutsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = WindowActionShortcutsWindowController()

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 350), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Window Action Shortcuts"
        window.center()
        self.init(window: window)
        window.delegate = self
        window.contentView = WindowActionShortcutsView(frame: window.contentView!.bounds)
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        (window?.contentView as? WindowActionShortcutsView)?.stopRecording()
    }
}

final class WindowActionShortcutsView: NSView {
    private var buttons: [WindowAction: NSButton] = [:]
    private var recordingAction: WindowAction?
    private var localMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildControls()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildControls()
    }

    deinit {
        stopRecording()
    }

    private func buildControls() {
        autoresizingMask = [.width, .height]

        let title = NSTextField(labelWithString: "Window actions")
        title.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        title.frame = NSRect(x: 24, y: bounds.height - 48, width: bounds.width - 48, height: 30)
        title.autoresizingMask = [.width, .minYMargin]
        addSubview(title)

        let subtitle = NSTextField(labelWithString: "Click a shortcut, then press a key combination. Use at least one modifier.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 26, y: bounds.height - 74, width: bounds.width - 52, height: 18)
        subtitle.autoresizingMask = [.width, .minYMargin]
        addSubview(subtitle)

        for (index, action) in WindowAction.allCases.enumerated() {
            let y = bounds.height - 112 - CGFloat(index) * 40
            let label = NSTextField(labelWithString: action.title)
            label.frame = NSRect(x: 26, y: y + 4, width: 260, height: 20)
            label.autoresizingMask = [.minYMargin]
            addSubview(label)

            let button = NSButton(title: SettingsStore.windowActionShortcut(for: action).displayName, target: self, action: #selector(beginRecording(_:)))
            button.bezelStyle = .rounded
            button.alignment = .center
            button.tag = index
            button.frame = NSRect(x: 300, y: y, width: 210, height: 28)
            button.autoresizingMask = [.minXMargin, .minYMargin]
            addSubview(button)
            buttons[action] = button
        }

        let resetButton = NSButton(title: "Reset defaults", target: self, action: #selector(resetDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 26, y: 18, width: 120, height: 28)
        resetButton.autoresizingMask = [.minYMargin]
        addSubview(resetButton)
    }

    @objc private func beginRecording(_ sender: NSButton) {
        guard WindowAction.allCases.indices.contains(sender.tag) else { return }
        let action = WindowAction.allCases[sender.tag]
        stopRecording()
        recordingAction = action
        sender.title = "Press shortcut..."
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.recordingAction else { return event }
            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }

            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !modifiers.isEmpty else {
                self.showError("Use Command, Option, Control, or Shift with the key.")
                return nil
            }

            let shortcut = WindowActionShortcut(keyCode: event.keyCode, modifierRawValue: modifiers.rawValue)
            if let conflict = SettingsStore.windowActionShortcutConflict(shortcut, for: action) {
                self.showError(conflict)
                return nil
            }
            guard SettingsStore.setWindowActionShortcut(shortcut, for: action) else {
                self.showError("Could not save that shortcut.")
                return nil
            }
            self.stopRecording()
            return nil
        }
    }

    fileprivate func stopRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        if let recordingAction,
           let button = buttons[recordingAction] {
            button.title = SettingsStore.windowActionShortcut(for: recordingAction).displayName
        }
        recordingAction = nil
    }

    @objc private func resetDefaults() {
        stopRecording()
        for action in WindowAction.allCases {
            SettingsStore.resetWindowActionShortcut(for: action)
            buttons[action]?.title = SettingsStore.windowActionShortcut(for: action).displayName
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Shortcut not saved"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
