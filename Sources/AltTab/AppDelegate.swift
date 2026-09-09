import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = SwitcherController()
    private let accessibilityOnboarding = AccessibilityOnboardingController()
    private var statusItem: NSStatusItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsStore.registerDefaults()
        configureMenuBar()
        installKeyboardMonitors()
        accessibilityOnboarding.presentIfNeeded()
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
        menu.addItem(NSMenuItem(title: "Accessibility Permission...", action: #selector(showAccessibilitySettings), keyEquivalent: ""))
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
        if event.type == .flagsChanged {
            if switcher.isVisible && !event.modifierFlags.contains(.option) {
                switcher.commit()
                return true
            }
            return false
        }

        guard event.type == .keyDown else { return false }

        if switcher.isVisible {
            switch event.keyCode {
            case 36, 76:
                switcher.commit()
                return true
            case 53:
                switcher.cancel()
                return true
            case 48 where event.modifierFlags.contains(.option):
                if event.modifierFlags.contains(.shift) {
                    switcher.previous()
                } else {
                    switcher.advance()
                }
                return true
            case 123, 126:
                switcher.previous()
                return true
            case 124, 125:
                switcher.advance()
                return true
            default:
                if let index = SwitcherController.numberIndex(for: event.keyCode),
                   event.modifierFlags.intersection([.command, .control]).isEmpty {
                    switcher.select(index: index)
                    return true
                }
            }
        }

        if let slot = ShortcutStore.slot(for: event.keyCode) {
            ShortcutStore.activate(slot: slot)
            return true
        }

        if event.keyCode == 48, event.modifierFlags.contains(.option) {
            if !switcher.isVisible {
                switcher.begin()
            } else if event.modifierFlags.contains(.shift) {
                switcher.previous()
            } else {
                switcher.advance()
            }
            return true
        }
        return false
    }

    @objc private func showSwitcher() { switcher.begin() }
    @objc private func showAccessibilitySettings() { accessibilityOnboarding.showAlertIfNeeded() }
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

    func previous() {
        guard isVisible, !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
        view?.selectedIndex = selectedIndex
    }

    func select(index: Int) {
        guard isVisible, items.indices.contains(index) else { return }
        selectedIndex = index
        view?.selectedIndex = selectedIndex
    }

    static func numberIndex(for keyCode: UInt16) -> Int? {
        let keyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard let index = keyCodes.firstIndex(of: keyCode) else { return nil }
        return index
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
        view.onItemSelected = { [weak self] index in
            self?.select(index: index)
        }
        view.onItemCommitted = { [weak self] in
            self?.commit()
        }
        panel.contentView = view
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        self.panel = panel
        self.view = view
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        }
    }
}
