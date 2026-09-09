import AppKit
import Foundation

struct AppProfile: Codable, Equatable {
    let contentMode: String
    let showUtilityWindows: Bool
    let showMinimizedWindows: Bool
    let onlyCurrentDisplay: Bool
    let excludedBundleIdentifiers: [String]
    let thumbnailSize: Double
    let iconSize: Double
    let columns: Int
    let showLabels: Bool
    let cornerRadius: Double
    let opacity: Double
    let accentColorHex: String
    let backgroundBlur: Bool

    var resolvedContentMode: SwitcherContentMode {
        SwitcherContentMode(rawValue: contentMode) ?? .windows
    }
}

enum AppProfileStore {
    private static let key = "AltTab.workflow.appProfiles"

    static var allProfiles: [String: AppProfile] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profiles = try? JSONDecoder().decode([String: AppProfile].self, from: data) else { return [:] }
        return profiles
    }

    static var bundleIdentifiers: [String] {
        allProfiles.keys.sorted()
    }

    static func profile(for bundleIdentifier: String) -> AppProfile? {
        allProfiles[bundleIdentifier]
    }

    static func save(_ profile: AppProfile, for bundleIdentifier: String) {
        var profiles = allProfiles
        profiles[bundleIdentifier] = profile
        persist(profiles)
    }

    static func removeProfile(for bundleIdentifier: String) {
        var profiles = allProfiles
        profiles.removeValue(forKey: bundleIdentifier)
        persist(profiles)
    }

    static func replaceAll(_ profiles: [String: AppProfile]) {
        persist(profiles)
    }

    private static func persist(_ profiles: [String: AppProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
