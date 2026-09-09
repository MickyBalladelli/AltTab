import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = SwitcherController()
    private let accessibilityOnboarding = AccessibilityOnboardingController()
    private var statusItem: NSStatusItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pressedModifierKeyCodes = Set<UInt16>()
    private let commandPalette = CommandPaletteWindowController()

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
        let paletteItem = NSMenuItem(title: "Command Palette...", action: #selector(showCommandPalette), keyEquivalent: "p")
        paletteItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(paletteItem)
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Accessibility Permission...", action: #selector(showAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Diagnostics & Permissions...", action: #selector(showDiagnostics), keyEquivalent: ""))
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
            updateModifierState(for: event)
            if switcher.isVisible,
               SettingsStore.holdToPreview,
               ActivationShortcut.modifierKeyCodes.contains(event.keyCode),
               !SettingsStore.activationShortcut.matches(flags: event.modifierFlags, pressedKeyCodes: pressedModifierKeyCodes) {
                switcher.commit()
                return true
            }
            return false
        }

        guard event.type == .keyDown else { return false }

        if let index = SwitcherController.numberIndex(for: event.keyCode),
           event.modifierFlags.contains(.option) {
            switcher.activateWindow(at: index)
            return true
        }

        if switcher.isVisible {
            switch event.keyCode {
            case 36, 76:
                switcher.commit()
                return true
            case 53:
                if switcher.hasSearchQuery {
                    switcher.clearSearch()
                    return true
                }
                switcher.cancel()
                return true
            case 51, 117:
                if switcher.hasSearchQuery {
                    switcher.deleteSearchCharacter()
                    return true
                }
            case 48 where SettingsStore.activationShortcut.matches(flags: event.modifierFlags, pressedKeyCodes: pressedModifierKeyCodes):
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
                   !switcher.hasSearchQuery,
                   event.modifierFlags.intersection([.command, .control]).isEmpty {
                    switcher.select(index: index)
                    return true
                }
            }

            if event.modifierFlags.intersection([.command, .control]).isEmpty,
               let characters = event.charactersIgnoringModifiers,
               !characters.isEmpty {
                switcher.appendSearchText(characters)
                return true
            }
        }

        if let slot = ShortcutStore.slot(for: event) {
            ShortcutStore.activate(slot: slot)
            return true
        }

        if event.keyCode == 48,
           SettingsStore.activationShortcut.matches(flags: event.modifierFlags, pressedKeyCodes: pressedModifierKeyCodes) {
            switcher.begin()
            return true
        }
        return false
    }

    private func updateModifierState(for event: NSEvent) {
        let modifierFlag: NSEvent.ModifierFlags
        switch event.keyCode {
        case 58, 61:
            modifierFlag = .option
        case 54, 55:
            modifierFlag = .command
        default:
            return
        }

        if event.modifierFlags.contains(modifierFlag) {
            pressedModifierKeyCodes.insert(event.keyCode)
        } else {
            pressedModifierKeyCodes.remove(event.keyCode)
        }
    }

    @objc private func showSwitcher() { switcher.begin() }
    @objc private func showAccessibilitySettings() {
        if AccessibilityController.isTrusted {
            AccessibilityController.openSystemSettings()
        } else {
            accessibilityOnboarding.showAlertIfNeeded()
        }
    }
    @objc private func showSettings() { SettingsWindowController.shared.showWindow(nil) }
    @objc private func checkForUpdates() { UpdateController.shared.checkForUpdates() }
    @objc private func showCommandPalette() {
        commandPalette.show(
            showSwitcher: { [weak self] in self?.switcher.begin() },
            showSettings: { SettingsWindowController.shared.showWindow(nil) }
        )
    }
    @objc private func showDiagnostics() { DiagnosticsWindowController.shared.showWindow(nil) }
}

enum ShortcutStore {
    private static let keyPrefix = "AltTab.quickSlot."
    private static let keyCodeSuffix = ".keyCode"
    private static let modifiersSuffix = ".modifiers"
    private static let defaultKeyCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    private struct Binding: Codable {
        let slot: Int
        let bundleIdentifier: String?
        let keyCode: UInt16
        let modifiers: UInt
    }

    static func slot(for event: NSEvent) -> Int? {
        let modifiers = significantModifiers(for: event.modifierFlags)
        return (1...12).first { slot in
            guard UserDefaults.standard.string(forKey: keyPrefix + "\(slot)") != nil else { return false }
            let trigger = trigger(for: slot)
            return trigger.keyCode == event.keyCode && trigger.modifiers == modifiers
        }
    }

    static func activate(slot: Int) {
        guard let bundleID = UserDefaults.standard.string(forKey: keyPrefix + "\(slot)"),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    static func bundleIdentifier(for slot: Int) -> String? {
        UserDefaults.standard.string(forKey: keyPrefix + "\(slot)")
    }

    static func setBundleIdentifier(_ bundleIdentifier: String?, for slot: Int) {
        let key = keyPrefix + "\(slot)"
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            UserDefaults.standard.set(bundleIdentifier, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func trigger(for slot: Int) -> (keyCode: UInt16, modifiers: UInt) {
        let keyCodeKey = keyPrefix + "\(slot)" + keyCodeSuffix
        let modifiersKey = keyPrefix + "\(slot)" + modifiersSuffix
        guard UserDefaults.standard.object(forKey: keyCodeKey) != nil else {
            return (defaultKeyCodes[slot - 1], 0)
        }
        return (UInt16(UserDefaults.standard.integer(forKey: keyCodeKey)), UInt(UserDefaults.standard.integer(forKey: modifiersKey)))
    }

    static func setTrigger(keyCode: UInt16, modifiers: UInt, for slot: Int) {
        UserDefaults.standard.set(Int(keyCode), forKey: keyPrefix + "\(slot)" + keyCodeSuffix)
        UserDefaults.standard.set(Int(modifiers), forKey: keyPrefix + "\(slot)" + modifiersSuffix)
    }

    static func clear(slot: Int) {
        setBundleIdentifier(nil, for: slot)
        UserDefaults.standard.removeObject(forKey: keyPrefix + "\(slot)" + keyCodeSuffix)
        UserDefaults.standard.removeObject(forKey: keyPrefix + "\(slot)" + modifiersSuffix)
    }

    static func displayName(for slot: Int) -> String {
        let trigger = trigger(for: slot)
        let modifierNames: [(NSEvent.ModifierFlags, String)] = [(.command, "⌘"), (.option, "⌥"), (.control, "⌃"), (.shift, "⇧")]
        let modifiers = modifierNames.compactMap { trigger.modifiers & $0.0.rawValue != 0 ? $0.1 : nil }.joined()
        let keyName: String
        switch trigger.keyCode {
        case 122: keyName = "F1"
        case 120: keyName = "F2"
        case 99: keyName = "F3"
        case 118: keyName = "F4"
        case 96: keyName = "F5"
        case 97: keyName = "F6"
        case 98: keyName = "F7"
        case 100: keyName = "F8"
        case 101: keyName = "F9"
        case 109: keyName = "F10"
        case 103: keyName = "F11"
        case 111: keyName = "F12"
        case 48: keyName = "Tab"
        case 36, 76: keyName = "Return"
        case 53: keyName = "Escape"
        case 123: keyName = "Left Arrow"
        case 124: keyName = "Right Arrow"
        case 125: keyName = "Down Arrow"
        case 126: keyName = "Up Arrow"
        default: keyName = "Key \(trigger.keyCode)"
        }
        return modifiers + keyName
    }

    static func exportBindings() throws -> Data {
        let bindings = (1...12).map { slot in
            let trigger = trigger(for: slot)
            return Binding(slot: slot, bundleIdentifier: bundleIdentifier(for: slot), keyCode: trigger.keyCode, modifiers: trigger.modifiers)
        }
        return try JSONEncoder().encode(bindings)
    }

    static func importBindings(_ data: Data) throws {
        let bindings = try JSONDecoder().decode([Binding].self, from: data)
        for binding in bindings where (1...12).contains(binding.slot) {
            setTrigger(keyCode: binding.keyCode, modifiers: binding.modifiers, for: binding.slot)
            setBundleIdentifier(binding.bundleIdentifier, for: binding.slot)
        }
    }

    private static func significantModifiers(for flags: NSEvent.ModifierFlags) -> UInt {
        flags.intersection([.command, .option, .control, .shift]).rawValue
    }
}

final class SwitcherController {
    private(set) var isVisible = false
    private var items: [SwitcherItem] = []
    private var sourceItems: [SwitcherItem] = []
    private(set) var searchQuery = ""
    private var selectedIndex = 0
    private var panel: NSPanel?
    private var view: SwitcherView?
    private var blurView: NSVisualEffectView?
    var hasSearchQuery: Bool { !searchQuery.isEmpty }

    func begin() {
        SettingsStore.registerDefaults()
        sourceItems = MRUStore.order(WindowCatalog.items(for: SettingsStore.contentMode))
        guard !sourceItems.isEmpty else { return }
        searchQuery = ""
        items = sourceItems
        selectedIndex = 0
        isVisible = true
        if panel == nil { createPanel() }
        updatePanelAppearance()
        updatePanelLayout()
        view?.items = items
        view?.searchQuery = searchQuery
        view?.selectedIndex = selectedIndex
        panel?.orderFrontRegardless()
        announceSelection()
    }

    func advance() {
        guard isVisible, !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
        view?.selectedIndex = selectedIndex
        announceSelection()
    }

    func previous() {
        guard isVisible, !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
        view?.selectedIndex = selectedIndex
        announceSelection()
    }

    func select(index: Int) {
        guard isVisible, items.indices.contains(index) else { return }
        selectedIndex = index
        view?.selectedIndex = selectedIndex
        announceSelection()
    }

    func appendSearchText(_ text: String) {
        guard isVisible else { return }
        let additions = text.filter { !$0.isNewline && $0 != "\u{7f}" }
        guard !additions.isEmpty else { return }
        searchQuery.append(contentsOf: additions)
        applySearch()
    }

    func deleteSearchCharacter() {
        guard isVisible, !searchQuery.isEmpty else { return }
        searchQuery.removeLast()
        applySearch()
    }

    func clearSearch() {
        guard isVisible, !searchQuery.isEmpty else { return }
        searchQuery = ""
        applySearch()
    }

    func activateWindow(at index: Int) {
        let windows = MRUStore.order(WindowCatalog.items(for: .windows))
        guard windows.indices.contains(index) else { return }
        MRUStore.record(windows[index])
        windows[index].activate()
        cancel()
    }

    static func numberIndex(for keyCode: UInt16) -> Int? {
        let keyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard let index = keyCodes.firstIndex(of: keyCode) else { return nil }
        return index
    }

    func commit() {
        guard isVisible, items.indices.contains(selectedIndex) else { cancel(); return }
        MRUStore.record(items[selectedIndex])
        items[selectedIndex].activate()
        cancel()
    }

    func cancel() {
        isVisible = false
        panel?.orderOut(nil)
        searchQuery = ""
        view?.searchQuery = searchQuery
    }

    private func createPanel() {
        let size = SwitcherView.preferredSize(for: max(items.count, 1))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.animationBehavior = SystemAccessibility.reduceMotion ? .none : .utilityWindow
        let view = SwitcherView(frame: NSRect(origin: .zero, size: size))
        view.onItemSelected = { [weak self] index in
            self?.select(index: index)
        }
        view.onItemCommitted = { [weak self] in
            self?.commit()
        }
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        self.panel = panel
        self.view = view
        updatePanelAppearance()
    }

    private func updatePanelLayout() {
        guard let panel, let view else { return }
        let size = SwitcherView.preferredSize(for: max(items.count, 1))
        panel.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        if let contentView = panel.contentView {
            contentView.frame = NSRect(origin: .zero, size: size)
        }
        let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        if let screen = mouseScreen ?? NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        }
    }

    private func updatePanelAppearance() {
        guard let panel, let view else { return }
        if SettingsStore.backgroundBlur && !SystemAccessibility.reduceTransparency {
            let effect = blurView ?? NSVisualEffectView(frame: panel.contentView?.bounds ?? view.bounds)
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.autoresizingMask = [.width, .height]
            blurView = effect
            if panel.contentView !== effect {
                panel.contentView = effect
            }
            if view.superview !== effect {
                view.removeFromSuperview()
                effect.addSubview(view)
            }
            view.frame = effect.bounds
            view.autoresizingMask = [.width, .height]
        } else {
            view.removeFromSuperview()
            panel.contentView = view
            view.frame = panel.contentView?.bounds ?? view.bounds
            view.autoresizingMask = [.width, .height]
        }
        panel.animationBehavior = SystemAccessibility.reduceMotion ? .none : .utilityWindow
    }

    private func applySearch() {
        let previousIdentifier = items.indices.contains(selectedIndex) ? items[selectedIndex].identifier : nil
        if searchQuery.isEmpty {
            items = sourceItems
        } else {
            items = sourceItems.filter { item in
                item.title.localizedCaseInsensitiveContains(searchQuery) ||
                item.subtitle.localizedCaseInsensitiveContains(searchQuery) ||
                (item.app?.localizedName?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            }
        }
        selectedIndex = previousIdentifier.flatMap { identifier in
            items.firstIndex { $0.identifier == identifier }
        } ?? 0
        view?.items = items
        view?.searchQuery = searchQuery
        view?.selectedIndex = selectedIndex
        announceSelection()
    }

    private func announceSelection() {
        guard SystemAccessibility.voiceOverEnabled,
              let view,
              items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        let announcement = item.title + ", " + item.subtitle
        NSAccessibility.post(
            element: view,
            notification: .announcementRequested,
            userInfo: [.announcement: announcement]
        )
    }
}
