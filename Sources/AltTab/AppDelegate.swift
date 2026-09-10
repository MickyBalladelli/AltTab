import AppKit
import CoreGraphics
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = SwitcherController()
    private let accessibilityOnboarding = AccessibilityOnboardingController()
    private var statusItem: NSStatusItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pressedModifierKeyCodes = Set<UInt16>()
    private var commandTabEventTap: CFMachPort?
    private var commandTabEventSource: CFRunLoopSource?
    private var commandTabRetryTimer: Timer?
    private let commandPalette = CommandPaletteWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsStore.registerDefaults()
        CrashDiagnostics.install()
        switcher.onAccessibilityLost = { [weak self] in
            self?.recoverAccessibility()
        }
        switcher.onWindowActivationFailure = { [weak self] in
            self?.showWindowActivationError()
        }
        configureMenuBar()
        installKeyboardMonitors()
        installCommandTabEventTap()
        accessibilityOnboarding.presentIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        commandTabRetryTimer?.invalidate()
        if let commandTabEventSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), commandTabEventSource, .commonModes)
        }
        if let commandTabEventTap {
            CGEvent.tapEnable(tap: commandTabEventTap, enable: false)
            CFMachPortInvalidate(commandTabEventTap)
        }
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
        menu.addItem(NSMenuItem(title: "Window Action Shortcuts...", action: #selector(showWindowActionShortcuts), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Workflow Settings...", action: #selector(showWorkflowSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "App Profiles...", action: #selector(showAppProfiles), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Export Settings...", action: #selector(exportSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Import Settings...", action: #selector(importSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Diagnostics & Permissions...", action: #selector(showDiagnostics), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Crash Diagnostics...", action: #selector(openCrashDiagnostics), keyEquivalent: ""))
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

    private func installCommandTabEventTap() {
        guard commandTabEventTap == nil else { return }

        let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.tapDisabledByTimeout.rawValue)
            | (CGEventMask(1) << CGEventType.tapDisabledByUserInput.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let eventTap = CGEvent.tapCreate(
            // HID taps are restricted to root. Session taps are the supported
            // choice for an Accessibility-enabled app and still run before
            // events are delivered to the active application.
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.commandTabEventTapCallback,
            userInfo: userInfo
        ) else {
            if commandTabRetryTimer == nil {
                commandTabRetryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                    guard let self else {
                        timer.invalidate()
                        return
                    }
                    self.installCommandTabEventTap()
                    if self.commandTabEventTap != nil {
                        timer.invalidate()
                        self.commandTabRetryTimer = nil
                    }
                }
            }
            return
        }

        commandTabEventTap = eventTap
        commandTabEventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let commandTabEventSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), commandTabEventSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        commandTabRetryTimer?.invalidate()
        commandTabRetryTimer = nil
    }

    private static let commandTabEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
        return appDelegate.handleCommandTabEvent(type: type, event: event)
    }

    private func handleCommandTabEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let commandTabEventTap {
                CGEvent.tapEnable(tap: commandTabEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let wasPressed = pressedModifierKeyCodes.contains(keyCode)
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            let isCommandActivation = SettingsStore.activationShortcut.modifierFlag == .command
            updateModifierState(keyCode: keyCode, flags: event.flags)
            if wasPressed,
               isCommandActivation,
               switcher.isActive,
               switcher.shouldCommitOnModifierRelease,
               SettingsStore.holdToPreview,
               ActivationShortcut.modifierKeyCodes.contains(keyCode),
               !SettingsStore.activationShortcut.matches(flags: modifiers, pressedKeyCodes: pressedModifierKeyCodes) {
                if switcher.isLoading {
                    switcher.cancel()
                } else {
                    switcher.commit()
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              event.getIntegerValueField(.keyboardEventKeycode) == 48 else {
            return Unmanaged.passUnretained(event)
        }

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        guard SettingsStore.activationShortcut.matches(flags: modifiers, pressedKeyCodes: pressedModifierKeyCodes) else {
            return Unmanaged.passUnretained(event)
        }

        if switcher.isLoading {
            return nil
        }
        if switcher.isVisible {
            if modifiers.contains(.shift) {
                switcher.previous()
            } else {
                switcher.advance()
            }
        } else {
            beginSwitcher()
        }
        return nil
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        if event.type == .flagsChanged {
            updateModifierState(for: event)
            if switcher.isActive,
               switcher.shouldCommitOnModifierRelease,
               SettingsStore.holdToPreview,
               ActivationShortcut.modifierKeyCodes.contains(event.keyCode),
               !SettingsStore.activationShortcut.matches(flags: event.modifierFlags, pressedKeyCodes: pressedModifierKeyCodes) {
                if switcher.isLoading {
                    switcher.cancel()
                } else {
                    switcher.commit()
                }
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

        if switcher.isLoading {
            if event.keyCode == 53 {
                switcher.cancel()
            }
            return true
        }

        if switcher.isVisible {
            if switcher.performWindowActionShortcut(event) {
                return true
            }
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
            case 126 where event.modifierFlags.contains(.option):
                switcher.recallRecentSearch(direction: -1)
                return true
            case 125 where event.modifierFlags.contains(.option):
                switcher.recallRecentSearch(direction: 1)
                return true
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
            beginSwitcher()
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

    private func updateModifierState(keyCode: UInt16, flags: CGEventFlags) {
        let modifierFlag: CGEventFlags
        switch keyCode {
        case 58, 61:
            modifierFlag = .maskAlternate
        case 54, 55:
            modifierFlag = .maskCommand
        default:
            return
        }

        if flags.contains(modifierFlag) {
            pressedModifierKeyCodes.insert(keyCode)
        } else {
            pressedModifierKeyCodes.remove(keyCode)
        }
    }

    @objc private func showSwitcher() { beginSwitcher() }
    @objc private func showAccessibilitySettings() {
        if AccessibilityController.isTrusted {
            AccessibilityController.openSystemSettings()
        } else {
            accessibilityOnboarding.showAlertIfNeeded()
        }
    }
    @objc private func showSettings() { SettingsWindowController.shared.showWindow(nil) }
    @objc private func showWindowActionShortcuts() { WindowActionShortcutsWindowController.shared.showWindow(nil) }
    @objc private func showWorkflowSettings() { WorkflowSettingsWindowController.shared.showWindow(nil) }
    @objc private func showAppProfiles() { AppProfilesWindowController.shared.showWindow(nil) }
    @objc private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "AltTab-settings.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsStore.exportPreferences().write(to: url, options: .atomic)
        } catch {
            showSettingsError(error.localizedDescription)
        }
    }
    @objc private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsStore.importPreferences(Data(contentsOf: url))
        } catch {
            showSettingsError(error.localizedDescription)
        }
    }
    @objc private func checkForUpdates() { UpdateController.shared.checkForUpdates() }
    @objc private func showCommandPalette() {
        commandPalette.show(
            showSwitcher: { [weak self] in self?.beginSwitcher() },
            showSettings: { SettingsWindowController.shared.showWindow(nil) }
        )
    }
    @objc private func showDiagnostics() { DiagnosticsWindowController.shared.showWindow(nil) }
    @objc private func openCrashDiagnostics() { CrashDiagnostics.openFolder() }

    private func beginSwitcher() {
        guard AccessibilityController.isTrusted else {
            accessibilityOnboarding.showAlertIfNeeded()
            return
        }
        switcher.begin()
    }

    private func recoverAccessibility() {
        switcher.cancel()
        accessibilityOnboarding.showAlertIfNeeded()
    }

    private func showWindowActivationError() {
        let alert = NSAlert()
        alert.messageText = "Window is no longer available"
        alert.informativeText = "The window may have closed or moved while AltTab was open."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showSettingsError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Settings backup failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
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

    enum Error: LocalizedError {
        case conflict(String)

        var errorDescription: String? {
            switch self {
            case .conflict(let message): return message
            }
        }
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

    @discardableResult
    static func setBundleIdentifier(_ bundleIdentifier: String?, for slot: Int) -> Bool {
        let key = keyPrefix + "\(slot)"
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            let trigger = trigger(for: slot)
            guard conflict(for: slot, keyCode: trigger.keyCode, modifiers: trigger.modifiers) == nil else { return false }
            UserDefaults.standard.set(bundleIdentifier, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return true
    }

    static func defaultKeyCode(for slot: Int) -> UInt16? {
        guard (1...defaultKeyCodes.count).contains(slot) else { return nil }
        return defaultKeyCodes[slot - 1]
    }

    static func trigger(for slot: Int) -> (keyCode: UInt16, modifiers: UInt) {
        let keyCodeKey = keyPrefix + "\(slot)" + keyCodeSuffix
        let modifiersKey = keyPrefix + "\(slot)" + modifiersSuffix
        guard UserDefaults.standard.object(forKey: keyCodeKey) != nil else {
            return (defaultKeyCode(for: slot) ?? 0, 0)
        }
        return (UInt16(UserDefaults.standard.integer(forKey: keyCodeKey)), UInt(UserDefaults.standard.integer(forKey: modifiersKey)))
    }

    @discardableResult
    static func setTrigger(keyCode: UInt16, modifiers: UInt, for slot: Int) -> Bool {
        guard conflict(for: slot, keyCode: keyCode, modifiers: modifiers) == nil else { return false }
        UserDefaults.standard.set(Int(keyCode), forKey: keyPrefix + "\(slot)" + keyCodeSuffix)
        UserDefaults.standard.set(Int(modifiers), forKey: keyPrefix + "\(slot)" + modifiersSuffix)
        return true
    }

    static func clear(slot: Int) {
        setBundleIdentifier(nil, for: slot)
        UserDefaults.standard.removeObject(forKey: keyPrefix + "\(slot)" + keyCodeSuffix)
        UserDefaults.standard.removeObject(forKey: keyPrefix + "\(slot)" + modifiersSuffix)
    }

    static func conflict(for slot: Int, keyCode: UInt16, modifiers: UInt) -> String? {
        guard (1...12).contains(slot) else { return "That quick slot does not exist." }

        let activationModifiers = SettingsStore.activationShortcut.modifierFlag.rawValue
        if keyCode == 48 && modifiers == activationModifiers {
            return "This trigger conflicts with AltTab's activation shortcut."
        }

        for otherSlot in 1...12 where otherSlot != slot {
            guard UserDefaults.standard.string(forKey: keyPrefix + "\(otherSlot)") != nil else { continue }
            let otherTrigger = trigger(for: otherSlot)
            if otherTrigger.keyCode == keyCode && otherTrigger.modifiers == modifiers {
                return "This trigger is already assigned to slot F\(otherSlot)."
            }
        }
        return nil
    }

    static func conflict(withActivationShortcut shortcut: ActivationShortcut) -> String? {
        let activationModifiers = shortcut.modifierFlag.rawValue
        for slot in 1...12 {
            guard UserDefaults.standard.string(forKey: keyPrefix + "\(slot)") != nil else { continue }
            let trigger = trigger(for: slot)
            if trigger.keyCode == 48 && trigger.modifiers == activationModifiers {
                return "This activation shortcut conflicts with active quick slot F\(slot)."
            }
        }
        return nil
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
            guard setTrigger(keyCode: binding.keyCode, modifiers: binding.modifiers, for: binding.slot) else {
                let reason = conflict(for: binding.slot, keyCode: binding.keyCode, modifiers: binding.modifiers) ?? "trigger conflict"
                throw Error.conflict("Could not import slot F\(binding.slot): \(reason)")
            }
            guard setBundleIdentifier(binding.bundleIdentifier, for: binding.slot) else {
                let trigger = trigger(for: binding.slot)
                let reason = conflict(for: binding.slot, keyCode: trigger.keyCode, modifiers: trigger.modifiers) ?? "trigger conflict"
                throw Error.conflict("Could not import slot F\(binding.slot): \(reason)")
            }
        }
    }

    private static func significantModifiers(for flags: NSEvent.ModifierFlags) -> UInt {
        flags.intersection([.command, .option, .control, .shift]).rawValue
    }
}

final class SwitcherController {
    var onAccessibilityLost: (() -> Void)?
    var onWindowActivationFailure: (() -> Void)?
    private var state = SwitcherState()
    private var panel: NSPanel?
    private var view: SwitcherView?
    private var blurView: NSVisualEffectView?
    private var loadGeneration = 0
    private var loading = false
    private var holdToPreviewSession = false
    private var recentSearchIndex: Int?
    private var settingsBeforeAppProfile: AppProfile?
    var isVisible: Bool { state.isVisible }
    var isLoading: Bool { loading }
    var isActive: Bool { isVisible || isLoading }
    var shouldCommitOnModifierRelease: Bool { holdToPreviewSession }
    var searchQuery: String { state.searchQuery }
    var hasSearchQuery: Bool { state.hasSearchQuery }
    private var items: [SwitcherItem] { state.items }
    private var selectedIndex: Int { state.selectedIndex }

    func begin() {
        SettingsStore.registerDefaults()
        restoreAppProfile()
        let appProfile = frontmostAppProfile()
        if let appProfile {
            settingsBeforeAppProfile = SettingsStore.profileSnapshot()
            SettingsStore.apply(appProfile)
        }
        let mode = appProfile == nil ? SettingsStore.modeForNextSwitcher : SettingsStore.contentMode
        loadGeneration += 1
        let generation = loadGeneration
        loading = true
        holdToPreviewSession = true
        recentSearchIndex = nil
        WindowCatalog.loadItems(for: mode) { [weak self] loadedItems in
            guard let self, self.loadGeneration == generation else { return }
            self.loading = false
            let orderedItems = MRUStore.order(loadedItems)
            guard self.state.begin(items: orderedItems) else {
                self.panel?.orderOut(nil)
                self.restoreAppProfile()
                self.syncView()
                return
            }
            if appProfile == nil {
                SettingsStore.lastMode = mode
            }
            if self.panel == nil { self.createPanel() }
            self.updatePanelAppearance()
            self.updatePanelLayout()
            self.syncView()
            self.panel?.orderFrontRegardless()
            self.announceSelection()
        }
    }

    func advance() {
        guard state.advance() else { return }
        syncView()
        announceSelection()
    }

    func previous() {
        guard state.previous() else { return }
        syncView()
        announceSelection()
    }

    func select(index: Int) {
        guard state.select(index: index) else { return }
        syncView()
        announceSelection()
    }

    func appendSearchText(_ text: String) {
        recentSearchIndex = nil
        guard state.appendSearchText(text) else { return }
        syncView()
        announceSelection()
    }

    func deleteSearchCharacter() {
        recentSearchIndex = nil
        guard state.deleteSearchCharacter() else { return }
        syncView()
        announceSelection()
    }

    func clearSearch() {
        recentSearchIndex = nil
        guard state.clearSearch() else { return }
        syncView()
        announceSelection()
    }

    func activateWindow(at index: Int) {
        loadGeneration += 1
        let generation = loadGeneration
        loading = true
        holdToPreviewSession = false
        WindowCatalog.loadItems(for: .windows) { [weak self] loadedItems in
            guard let self, self.loadGeneration == generation else { return }
            self.loading = false
            let windows = MRUStore.order(loadedItems)
            guard windows.indices.contains(index) else { return }
            guard windows[index].activate() else {
                self.reportActivationFailure()
                return
            }
            MRUStore.record(windows[index])
            if self.isVisible {
                self.cancel()
            }
        }
    }

    func recallRecentSearch(direction: Int) {
        let terms = SearchHistoryStore.terms
        guard !terms.isEmpty else { return }
        let nextIndex: Int
        if let recentSearchIndex {
            nextIndex = (recentSearchIndex + direction + terms.count) % terms.count
        } else {
            nextIndex = direction < 0 ? 0 : terms.count - 1
        }
        recentSearchIndex = nextIndex
        guard state.setSearchQuery(terms[nextIndex]) else { return }
        syncView()
        announceSelection()
    }

    func performWindowActionShortcut(_ event: NSEvent) -> Bool {
        guard let action = WindowAction.allCases.first(where: { SettingsStore.windowActionShortcut(for: $0).matches(event) }) else { return false }
        guard let item = state.selectedItem else { return true }
        performWindowAction(action, on: item)
        return true
    }

    static func numberIndex(for keyCode: UInt16) -> Int? {
        let keyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard let index = keyCodes.firstIndex(of: keyCode) else { return nil }
        return index
    }

    func commit() {
        guard !loading else {
            cancel()
            return
        }
        guard let item = state.selectedItem else { cancel(); return }
        let query = state.searchQuery
        guard item.activate() else {
            state.removeSelected()
            syncView()
            if !state.isVisible {
                panel?.orderOut(nil)
            }
            reportActivationFailure()
            return
        }
        MRUStore.record(item)
        SearchHistoryStore.record(query)
        state.cancel()
        restoreAppProfile()
        syncView()
        panel?.orderOut(nil)
    }

    func cancel() {
        loadGeneration += 1
        loading = false
        holdToPreviewSession = false
        state.cancel()
        restoreAppProfile()
        panel?.orderOut(nil)
        syncView()
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
        view.onContextMenu = { [weak self] index in
            self?.contextMenu(for: index)
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

    private func syncView() {
        view?.items = items
        view?.searchQuery = searchQuery
        view?.selectedIndex = selectedIndex
        view?.recentSearchTerms = SearchHistoryStore.terms
    }

    private func frontmostAppProfile() -> AppProfile? {
        let currentProcessIdentifier = NSRunningApplication.current.processIdentifier
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != currentProcessIdentifier,
              let bundleIdentifier = app.bundleIdentifier else { return nil }
        return AppProfileStore.profile(for: bundleIdentifier)
    }

    private func restoreAppProfile() {
        guard let settingsBeforeAppProfile else { return }
        SettingsStore.apply(settingsBeforeAppProfile)
        self.settingsBeforeAppProfile = nil
    }

    private func contextMenu(for index: Int) -> NSMenu? {
        guard state.select(index: index), let item = state.selectedItem else { return nil }
        syncView()

        let menu = NSMenu()
        for action in WindowAction.allCases where item.window != nil || action == .hideApp {
            let title: String
            if action == .moveToDisplay, let targetDisplay = WindowActionService.nextDisplayName(for: item) {
                title = "Move window to \(targetDisplay)"
            } else {
                title = action.title
            }
            let menuItem = NSMenuItem(title: title, action: #selector(performContextAction(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = action.rawValue
            let shortcut = SettingsStore.windowActionShortcut(for: action).displayName
            menuItem.toolTip = "Shortcut: \(shortcut)"
            menu.addItem(menuItem)
        }
        return menu.items.isEmpty ? nil : menu
    }

    @objc private func performContextAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = WindowAction(rawValue: rawValue),
              let item = state.selectedItem else { return }
        performWindowAction(action, on: item)
    }

    private func performWindowAction(_ action: WindowAction, on item: SwitcherItem) {
        guard WindowActionService.performWithConfirmation(action, on: item) else { return }
        if [.close, .minimize, .hideApp].contains(action) {
            state.removeSelected()
            syncView()
            if !state.isVisible {
                panel?.orderOut(nil)
            }
        }
    }

    private func reportActivationFailure() {
        if AccessibilityController.isTrusted {
            onWindowActivationFailure?()
        } else {
            onAccessibilityLost?()
        }
    }

    private func announceSelection() {
        guard SystemAccessibility.voiceOverEnabled,
              let view,
              state.items.indices.contains(state.selectedIndex) else { return }
        let item = state.items[state.selectedIndex]
        let announcement = item.title + ", " + item.subtitle
        NSAccessibility.post(
            element: view,
            notification: .announcementRequested,
            userInfo: [.announcement: announcement]
        )
    }
}
