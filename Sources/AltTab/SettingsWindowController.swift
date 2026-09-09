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
    override func draw(_ dirtyRect: NSRect) {
        let title = "Make switching feel like yours."
        (title as NSString).draw(at: NSPoint(x: 32, y: bounds.height - 58), withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .bold)])
        ("Choose what appears in the switcher and set quick-launch keys for your everyday apps." as NSString).draw(at: NSPoint(x: 34, y: bounds.height - 88), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor])
        addControl(label: "Switcher shortcut", value: "Option + Tab", y: bounds.height - 140)
        addControl(label: "Visible items", value: "Windows", y: bounds.height - 190)
        addControl(label: "Window preview size", value: "Medium", y: bounds.height - 240)
        addControl(label: "Show window titles", value: "On", y: bounds.height - 290)
        addControl(label: "F1 - F12 app slots", value: "Configure...", y: bounds.height - 340)
        ("Tip: assign F1-F12 to apps in the menu bar settings to jump instantly." as NSString).draw(at: NSPoint(x: 34, y: 28), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor])
    }

    private func addControl(label: String, value: String, y: CGFloat) {
        (label as NSString).draw(at: NSPoint(x: 34, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        let button = NSPopUpButton(frame: NSRect(x: bounds.width - 190, y: y - 6, width: 156, height: 26), pullsDown: false)
        button.addItem(withTitle: value)
        button.bezelStyle = .rounded
        addSubview(button)
    }
}
