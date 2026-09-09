import Foundation

enum SettingsStore {
    static let showUtilityWindowsKey = "AltTab.filters.showUtilityWindows"
    static let showMinimizedWindowsKey = "AltTab.filters.showMinimizedWindows"
    static let excludedBundleIdentifiersKey = "AltTab.filters.excludedBundleIdentifiers"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showUtilityWindowsKey: false,
            showMinimizedWindowsKey: false,
            excludedBundleIdentifiersKey: []
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
}
