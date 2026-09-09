import Foundation

enum SettingsStore {
    static let showUtilityWindowsKey = "AltTab.filters.showUtilityWindows"
    static let showMinimizedWindowsKey = "AltTab.filters.showMinimizedWindows"
    static let excludedBundleIdentifiersKey = "AltTab.filters.excludedBundleIdentifiers"
    static let contentModeKey = "AltTab.customization.contentMode"
    static let thumbnailSizeKey = "AltTab.customization.thumbnailSize"
    static let iconSizeKey = "AltTab.customization.iconSize"
    static let columnsKey = "AltTab.customization.columns"
    static let showLabelsKey = "AltTab.customization.showLabels"
    static let cornerRadiusKey = "AltTab.customization.cornerRadius"
    static let opacityKey = "AltTab.customization.opacity"
    static let accentColorKey = "AltTab.customization.accentColor"
    static let backgroundBlurKey = "AltTab.customization.backgroundBlur"
    static let onlyCurrentDisplayKey = "AltTab.customization.onlyCurrentDisplay"
    static let activationShortcutKey = "AltTab.customization.activationShortcut"
    static let holdToPreviewKey = "AltTab.customization.holdToPreview"
    static let rememberLastModeKey = "AltTab.workflow.rememberLastMode"
    static let lastModeKey = "AltTab.workflow.lastMode"
    private static let windowActionShortcutPrefix = "AltTab.workflow.windowActionShortcut."

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showUtilityWindowsKey: false,
            showMinimizedWindowsKey: false,
            excludedBundleIdentifiersKey: [],
            contentModeKey: SwitcherContentMode.windows.rawValue,
            thumbnailSizeKey: 48.0,
            iconSizeKey: 48.0,
            columnsKey: 5,
            showLabelsKey: true,
            cornerRadiusKey: 18.0,
            opacityKey: 0.96,
            accentColorKey: "#0A84FF",
            backgroundBlurKey: true,
            onlyCurrentDisplayKey: false,
            activationShortcutKey: ActivationShortcut.option.rawValue,
            holdToPreviewKey: true,
            rememberLastModeKey: true
        ])
    }

    static var showUtilityWindows: Bool {
        get { UserDefaults.standard.bool(forKey: showUtilityWindowsKey) }
        set { UserDefaults.standard.set(newValue, forKey: showUtilityWindowsKey) }
    }

    static var showMinimizedWindows: Bool {
        get { UserDefaults.standard.bool(forKey: showMinimizedWindowsKey) }
        set { UserDefaults.standard.set(newValue, forKey: showMinimizedWindowsKey) }
    }

    static var excludedBundleIdentifiers: Set<String> {
        let values = UserDefaults.standard.stringArray(forKey: excludedBundleIdentifiersKey) ?? []
        return Set(values.map { $0.lowercased() })
    }

    static func setExcludedBundleIdentifiers(_ value: String) {
        let identifiers = value
            .split { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, identifier in
                if !result.contains(identifier) {
                    result.append(identifier)
                }
            }
        UserDefaults.standard.set(identifiers, forKey: excludedBundleIdentifiersKey)
    }

    static var contentMode: SwitcherContentMode {
        get { SwitcherContentMode(rawValue: UserDefaults.standard.string(forKey: contentModeKey) ?? "") ?? .windows }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: contentModeKey) }
    }

    static var thumbnailSize: Double {
        get { UserDefaults.standard.double(forKey: thumbnailSizeKey) }
        set { UserDefaults.standard.set(min(max(newValue, 24), 96), forKey: thumbnailSizeKey) }
    }

    static var iconSize: Double {
        get { UserDefaults.standard.double(forKey: iconSizeKey) }
        set { UserDefaults.standard.set(min(max(newValue, 20), 80), forKey: iconSizeKey) }
    }

    static var columns: Int {
        get { min(max(UserDefaults.standard.integer(forKey: columnsKey), 1), 10) }
        set { UserDefaults.standard.set(min(max(newValue, 1), 10), forKey: columnsKey) }
    }

    static var showLabels: Bool {
        get { UserDefaults.standard.bool(forKey: showLabelsKey) }
        set { UserDefaults.standard.set(newValue, forKey: showLabelsKey) }
    }

    static var cornerRadius: Double {
        get { UserDefaults.standard.double(forKey: cornerRadiusKey) }
        set { UserDefaults.standard.set(min(max(newValue, 0), 32), forKey: cornerRadiusKey) }
    }

    static var opacity: Double {
        get { UserDefaults.standard.double(forKey: opacityKey) }
        set { UserDefaults.standard.set(min(max(newValue, 0.4), 1), forKey: opacityKey) }
    }

    static var accentColorHex: String {
        get { UserDefaults.standard.string(forKey: accentColorKey) ?? "#0A84FF" }
        set { UserDefaults.standard.set(newValue, forKey: accentColorKey) }
    }

    static var backgroundBlur: Bool {
        get { UserDefaults.standard.bool(forKey: backgroundBlurKey) }
        set { UserDefaults.standard.set(newValue, forKey: backgroundBlurKey) }
    }

    static var onlyCurrentDisplay: Bool {
        get { UserDefaults.standard.bool(forKey: onlyCurrentDisplayKey) }
        set { UserDefaults.standard.set(newValue, forKey: onlyCurrentDisplayKey) }
    }

    static var activationShortcut: ActivationShortcut {
        get { ActivationShortcut(rawValue: UserDefaults.standard.string(forKey: activationShortcutKey) ?? "") ?? .option }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: activationShortcutKey) }
    }

    static var holdToPreview: Bool {
        get { UserDefaults.standard.bool(forKey: holdToPreviewKey) }
        set { UserDefaults.standard.set(newValue, forKey: holdToPreviewKey) }
    }

    static var rememberLastMode: Bool {
        get { UserDefaults.standard.bool(forKey: rememberLastModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: rememberLastModeKey) }
    }

    static var lastMode: SwitcherContentMode? {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: lastModeKey) else { return nil }
            return SwitcherContentMode(rawValue: rawValue)
        }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: lastModeKey) }
    }

    static var modeForNextSwitcher: SwitcherContentMode {
        rememberLastMode ? (lastMode ?? contentMode) : contentMode
    }

    static func windowActionShortcut(for action: WindowAction) -> WindowActionShortcut {
        let key = windowActionShortcutPrefix + action.rawValue
        guard let data = UserDefaults.standard.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(WindowActionShortcut.self, from: data) else {
            return .defaultShortcut(for: action)
        }
        return shortcut
    }

    @discardableResult
    static func setWindowActionShortcut(_ shortcut: WindowActionShortcut, for action: WindowAction) -> Bool {
        guard windowActionShortcutConflict(shortcut, for: action) == nil,
              let data = try? JSONEncoder().encode(shortcut) else { return false }
        UserDefaults.standard.set(data, forKey: windowActionShortcutPrefix + action.rawValue)
        return true
    }

    static func resetWindowActionShortcut(for action: WindowAction) {
        UserDefaults.standard.removeObject(forKey: windowActionShortcutPrefix + action.rawValue)
    }

    static func windowActionShortcutConflict(_ shortcut: WindowActionShortcut, for action: WindowAction) -> String? {
        if shortcut.keyCode == 48,
           shortcut.modifiers.contains(SettingsStore.activationShortcut.modifierFlag) {
            return "This shortcut conflicts with AltTab's activation shortcut."
        }

        for otherAction in WindowAction.allCases where otherAction != action {
            if windowActionShortcut(for: otherAction) == shortcut {
                return "This shortcut is already assigned to \(otherAction.title)."
            }
        }
        return nil
    }
}
