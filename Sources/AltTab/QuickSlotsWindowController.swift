import AppKit
import UniformTypeIdentifiers

final class QuickSlotsWindowController: NSWindowController {
    static let shared = QuickSlotsWindowController()

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "F1-F12 Quick Slots"
        window.center()
        self.init(window: window)
        window.contentView = QuickSlotsView(frame: window.contentView!.bounds)
    }

    override func showWindow(_ sender: Any?) {
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class QuickSlotsView: NSView {
    private struct Row {
        let slot: Int
        let keyLabel: NSTextField
        let recordButton: NSButton
        let appPopup: NSPopUpButton
        let bundleField: NSTextField
    }

    private var rows: [Row] = []
    private var recordingSlot: Int?
    private var recordMonitor: Any?

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

        let title = makeLabel("F1-F12 quick app slots", size: 24, weight: .bold)
        title.frame = NSRect(x: 24, y: bounds.height - 54, width: 400, height: 30)
        title.autoresizingMask = [.minYMargin]
        addSubview(title)

        let subtitle = makeLabel("Record a trigger, pick a running app, or enter a bundle ID. Changes save immediately.", size: 13, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 26, y: bounds.height - 82, width: bounds.width - 52, height: 20)
        subtitle.autoresizingMask = [.width, .minYMargin]
        addSubview(subtitle)

        let exportButton = NSButton(title: "Export...", target: self, action: #selector(exportBindings))
        exportButton.bezelStyle = .rounded
        exportButton.frame = NSRect(x: bounds.width - 190, y: bounds.height - 76, width: 76, height: 28)
        exportButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(exportButton)

        let importButton = NSButton(title: "Import...", target: self, action: #selector(importBindings))
        importButton.bezelStyle = .rounded
        importButton.frame = NSRect(x: bounds.width - 105, y: bounds.height - 76, width: 76, height: 28)
        importButton.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(importButton)

        addSubview(makeHeader("Slot", x: 24, width: 42))
        addSubview(makeHeader("Trigger", x: 70, width: 155))
        addSubview(makeHeader("Running app", x: 235, width: 210))
        addSubview(makeHeader("Bundle ID", x: 455, width: 245))

        for slot in 1...12 {
            let row = makeRow(slot: slot, y: bounds.height - 125 - CGFloat(slot - 1) * 46)
            rows.append(row)
            addSubview(row.keyLabel)
            addSubview(row.recordButton)
            addSubview(row.appPopup)
            addSubview(row.bundleField)

            let saveButton = NSButton(title: "Save", target: self, action: #selector(saveBundle(_:)))
            saveButton.tag = slot
            saveButton.bezelStyle = .rounded
            saveButton.frame = NSRect(x: bounds.width - 106, y: row.bundleField.frame.minY, width: 50, height: 26)
            saveButton.autoresizingMask = [.minXMargin, .minYMargin]
            addSubview(saveButton)

            let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearSlot(_:)))
            clearButton.tag = slot
            clearButton.bezelStyle = .rounded
            clearButton.frame = NSRect(x: bounds.width - 52, y: row.bundleField.frame.minY, width: 48, height: 26)
            clearButton.autoresizingMask = [.minXMargin, .minYMargin]
            addSubview(clearButton)
        }
    }

    private func makeRow(slot: Int, y: CGFloat) -> Row {
        let keyLabel = NSTextField(labelWithString: ShortcutStore.displayName(for: slot))
        keyLabel.alignment = .right
        keyLabel.frame = NSRect(x: 70, y: y, width: 155, height: 26)
        keyLabel.autoresizingMask = [.minYMargin]

        let recordButton = NSButton(title: "Record", target: self, action: #selector(recordKey(_:)))
        recordButton.tag = slot
        recordButton.bezelStyle = .rounded
        recordButton.frame = NSRect(x: 24, y: y, width: 62, height: 26)
        recordButton.autoresizingMask = [.minYMargin]

        let appPopup = NSPopUpButton(frame: NSRect(x: 235, y: y, width: 210, height: 26), pullsDown: false)
        appPopup.tag = slot
        appPopup.target = self
        appPopup.action = #selector(selectRunningApp(_:))
        appPopup.autoresizingMask = [.width, .minYMargin]
        addRunningApps(to: appPopup, slot: slot)

        let bundleField = NSTextField(string: ShortcutStore.bundleIdentifier(for: slot) ?? "")
        bundleField.placeholderString = "com.example.App"
        bundleField.frame = NSRect(x: 455, y: y, width: bounds.width - 575, height: 26)
        bundleField.autoresizingMask = [.width, .minYMargin]

        return Row(slot: slot, keyLabel: keyLabel, recordButton: recordButton, appPopup: appPopup, bundleField: bundleField)
    }

    private func addRunningApps(to popup: NSPopUpButton, slot: Int) {
        popup.addItem(withTitle: "(Choose an app)")
        popup.item(at: 0)?.representedObject = ""
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        let savedBundleID = ShortcutStore.bundleIdentifier(for: slot)
        var hasSavedBundle = false
        for app in apps {
            guard let bundleID = app.bundleIdentifier else { continue }
            popup.addItem(withTitle: "\(app.localizedName ?? bundleID) (\(bundleID))")
            popup.item(at: popup.numberOfItems - 1)?.representedObject = bundleID
            if bundleID == savedBundleID {
                hasSavedBundle = true
                popup.selectItem(at: popup.numberOfItems - 1)
            }
        }

        if let savedBundleID, !savedBundleID.isEmpty, !hasSavedBundle {
            popup.addItem(withTitle: "Saved: \(savedBundleID)")
            popup.item(at: popup.numberOfItems - 1)?.representedObject = savedBundleID
            popup.selectItem(at: popup.numberOfItems - 1)
        }
    }

    @objc private func selectRunningApp(_ sender: NSPopUpButton) {
        let bundleID = sender.selectedItem?.representedObject as? String ?? ""
        guard let row = rows.first(where: { $0.slot == sender.tag }) else { return }
        row.bundleField.stringValue = bundleID
        ShortcutStore.setBundleIdentifier(bundleID, for: sender.tag)
    }

    @objc private func saveBundle(_ sender: NSButton) {
        guard let row = rows.first(where: { $0.slot == sender.tag }) else { return }
        ShortcutStore.setBundleIdentifier(row.bundleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), for: row.slot)
        reloadRows()
    }

    @objc private func clearSlot(_ sender: NSButton) {
        ShortcutStore.clear(slot: sender.tag)
        stopRecording()
        reloadRows()
    }

    @objc private func recordKey(_ sender: NSButton) {
        stopRecording()
        recordingSlot = sender.tag
        sender.title = "Press key"
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recordingSlot != nil else { return event }
            if event.keyCode == 53 {
                self.stopRecording()
            } else {
                self.finishRecording(event)
            }
            return nil
        }
    }

    private func finishRecording(_ event: NSEvent) {
        guard let slot = recordingSlot else { return }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
        ShortcutStore.setTrigger(keyCode: event.keyCode, modifiers: modifiers, for: slot)
        stopRecording()
        reloadRows()
    }

    private func stopRecording() {
        if let recordMonitor {
            NSEvent.removeMonitor(recordMonitor)
        }
        recordMonitor = nil
        if let recordingSlot,
           let row = rows.first(where: { $0.slot == recordingSlot }) {
            row.recordButton.title = "Record"
        }
        recordingSlot = nil
    }

    private func reloadRows() {
        for row in rows {
            row.keyLabel.stringValue = ShortcutStore.displayName(for: row.slot)
            row.bundleField.stringValue = ShortcutStore.bundleIdentifier(for: row.slot) ?? ""
            row.appPopup.removeAllItems()
            addRunningApps(to: row.appPopup, slot: row.slot)
        }
    }

    @objc private func exportBindings() {
        do {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "AltTab-F1-F12.json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try ShortcutStore.exportBindings().write(to: url)
        } catch {
            showError("Could not export bindings: \(error.localizedDescription)")
        }
    }

    @objc private func importBindings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ShortcutStore.importBindings(Data(contentsOf: url))
            reloadRows()
        } catch {
            showError("Could not import bindings: \(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Quick slot error"
        alert.informativeText = message
        alert.runModal()
    }

    private func makeHeader(_ text: String, x: CGFloat, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: x, y: bounds.height - 108, width: width, height: 18)
        label.autoresizingMask = [.width, .minYMargin]
        return label
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        return label
    }

    deinit {
        stopRecording()
    }
}
