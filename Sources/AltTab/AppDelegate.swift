import AppKit
import ApplicationServices

struct WindowItem {
    let windowID: CGWindowID
    let app: NSRunningApplication
    let title: String
    let icon: NSImage

    func activate() {
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            guard titleValue as? String == title else { continue }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = SwitcherController()
    private var statusItem: NSStatusItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenuBar()
        installKeyboardMonitors()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "AltTab")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit AltTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func installKeyboardMonitors() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .keyDown, let slot = ShortcutStore.slot(for: event.keyCode) {
            ShortcutStore.activate(slot: slot)
            return true
        }
        guard event.keyCode == 48 else { return false }
        let optionPressed = event.modifierFlags.contains(.option)
        if event.type == .keyDown && optionPressed {
            if !switcher.isVisible { switcher.begin() } else { switcher.advance() }
            return true
        }
        if event.type == .keyDown && switcher.isVisible {
            if event.keyCode == 36 || event.keyCode == 76 {
                switcher.commit()
                return true
            }
            if event.keyCode == 53 {
                switcher.cancel()
                return true
            }
        }
        if event.type == .flagsChanged && !optionPressed && switcher.isVisible {
            switcher.commit()
            return true
        }
        return false
    }

    @objc private func showSwitcher() { switcher.begin() }
    @objc private func showSettings() { SettingsWindowController.shared.showWindow(nil) }
}

enum ShortcutStore {
    private static let keyPrefix = "AltTab.quickSlot."

    static func slot(for keyCode: UInt16) -> Int? {
        let keyCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        guard let index = keyCodes.firstIndex(of: keyCode), UserDefaults.standard.string(forKey: keyPrefix + "\(index + 1)") != nil else { return nil }
        return index + 1
    }

    static func activate(slot: Int) {
        guard let bundleID = UserDefaults.standard.string(forKey: keyPrefix + "\(slot)"),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}

final class SwitcherController {
    private(set) var isVisible = false
    private var items: [WindowItem] = []
    private var selectedIndex = 0
    private var panel: NSPanel?
    private var view: SwitcherView?

    func begin() {
        items = WindowCatalog.visibleWindows()
        guard !items.isEmpty else { return }
        selectedIndex = 0
        isVisible = true
        if panel == nil { createPanel() }
        view?.items = items
        view?.selectedIndex = selectedIndex
        panel?.orderFrontRegardless()
    }

    func advance() {
        guard isVisible, !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
        view?.selectedIndex = selectedIndex
    }

    func commit() {
        guard isVisible, items.indices.contains(selectedIndex) else { cancel(); return }
        items[selectedIndex].activate()
        cancel()
    }

    func cancel() {
        isVisible = false
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let size = NSSize(width: 680, height: 180)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = SwitcherView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = view
        self.panel = panel
        self.view = view
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        }
    }
}

final class WindowCatalog {
    static func visibleWindows() -> [WindowItem] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 80, (bounds["Height"] ?? 0) > 50,
                  let app = NSRunningApplication(processIdentifier: ownerPID),
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            let title = info[kCGWindowName as String] as? String ?? app.localizedName ?? "Window"
            return WindowItem(windowID: windowID, app: app, title: title.isEmpty ? (app.localizedName ?? "Window") : title, icon: app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
        }
    }
}
