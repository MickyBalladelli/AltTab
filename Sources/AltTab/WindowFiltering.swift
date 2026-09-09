import Foundation

struct WindowFilterOptions: Equatable {
    let includeOffScreen: Bool
    let showMinimizedWindows: Bool
    let showUtilityWindows: Bool
    let onlyCurrentDisplay: Bool
    let excludedBundleIdentifiers: Set<String>
}

struct WindowFilterCandidate: Equatable {
    let bundleIdentifier: String
    let layer: Int
    let width: CGFloat
    let height: CGFloat
    let isOnScreen: Bool
    let isMinimized: Bool
    let isUtility: Bool
    let isOnCurrentDisplay: Bool
}

enum WindowFilter {
    static func includes(_ candidate: WindowFilterCandidate, options: WindowFilterOptions) -> Bool {
        guard candidate.layer == 0,
              candidate.width > 80,
              candidate.height > 50 else { return false }

        let bundleIdentifier = candidate.bundleIdentifier.lowercased()
        guard !options.excludedBundleIdentifiers.contains(bundleIdentifier) else { return false }
        guard !options.onlyCurrentDisplay || candidate.isOnCurrentDisplay else { return false }

        if !options.includeOffScreen && !options.showMinimizedWindows && (!candidate.isOnScreen || candidate.isMinimized) {
            return false
        }
        if !options.includeOffScreen && options.showMinimizedWindows && !candidate.isOnScreen && !candidate.isMinimized {
            return false
        }
        if !options.showUtilityWindows && candidate.isUtility {
            return false
        }
        return true
    }
}
