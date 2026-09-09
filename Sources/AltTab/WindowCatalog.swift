import AppKit
import ApplicationServices

struct WindowItem {
    let windowID: CGWindowID
    let app: NSRunningApplication
    let title: String
    let icon: NSImage
    let isMinimized: Bool
    let frame: CGRect

    func activate() {
        app.activate(options: [.activateIgnoringOtherApps])

        let application = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }

        let matchingWindow = windows.first { window in
            WindowCatalog.windowID(for: window) == windowID
        } ?? windows.first { window in
            guard let candidateFrame = WindowCatalog.frame(for: window) else { return false }
            return WindowCatalog.framesMatch(candidateFrame, frame)
        } ?? windows.first { window in
            WindowCatalog.title(for: window) == title
        }

        guard let window = matchingWindow else { return }
        if isMinimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

final class WindowCatalog {
    private struct AccessibilityWindow {
        let id: CGWindowID?
        let title: String
        let frame: CGRect?
        let isMinimized: Bool
        let isUtility: Bool
    }

    private static let windowNumberAttribute = "AXWindowNumber" as CFString
    private static let utilitySubrole = "AXUtilityWindow"

    static func visibleWindows() -> [WindowItem] {
        SettingsStore.registerDefaults()

        let listOptions: CGWindowListOption = SettingsStore.showMinimizedWindows
            ? [.optionAll, .excludeDesktopElements]
            : [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(listOptions, kCGNullWindowID) as? [[String: Any]] else { return [] }

        var accessibilityCache: [pid_t: [AccessibilityWindow]] = [:]
        var seenWindowIDs = Set<CGWindowID>()

        return list.compactMap { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 80, (bounds["Height"] ?? 0) > 50,
                  let app = NSRunningApplication(processIdentifier: ownerPID),
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  seenWindowIDs.insert(windowID).inserted else { return nil }

            guard !SettingsStore.excludedBundleIdentifiers.contains((app.bundleIdentifier ?? "").lowercased()) else { return nil }

            let windowFrame = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            let windows = accessibilityCache[ownerPID] ?? accessibilityWindows(for: app)
            accessibilityCache[ownerPID] = windows
            let accessibilityWindow = windows.first { $0.id == windowID } ?? windows.first { candidate in
                guard let candidateFrame = candidate.frame else { return false }
                return framesMatch(candidateFrame, windowFrame)
            }
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? true
            let isMinimized = accessibilityWindow?.isMinimized ?? !isOnScreen

            if !SettingsStore.showMinimizedWindows && (!isOnScreen || isMinimized) {
                return nil
            }
            if SettingsStore.showMinimizedWindows && !isOnScreen && !isMinimized {
                return nil
            }
            if !SettingsStore.showUtilityWindows && accessibilityWindow?.isUtility == true {
                return nil
            }

            let title = info[kCGWindowName as String] as? String ?? app.localizedName ?? "Window"
            let resolvedTitle = title.isEmpty ? (app.localizedName ?? "Window") : title
            let icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
            return WindowItem(windowID: windowID, app: app, title: resolvedTitle, icon: icon, isMinimized: isMinimized, frame: windowFrame)
        }
    }

    fileprivate static func windowID(for window: AXUIElement) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, windowNumberAttribute, &value) == .success,
              let number = value as? NSNumber else { return nil }
        return CGWindowID(number.uint32Value)
    }

    fileprivate static func title(for window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    fileprivate static func frame(for window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue else { return nil }

        let position = positionValue as! AXValue
        let size = sizeValue as! AXValue

        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetType(position) == .cgPoint,
              AXValueGetValue(position, .cgPoint, &point),
              AXValueGetType(size) == .cgSize,
              AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    fileprivate static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 2 &&
        abs(lhs.origin.y - rhs.origin.y) < 2 &&
        abs(lhs.width - rhs.width) < 2 &&
        abs(lhs.height - rhs.height) < 2
    }

    private static func accessibilityWindows(for app: NSRunningApplication) -> [AccessibilityWindow] {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }

        return windows.map { window in
            var minimizedValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)

            var subroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)

            return AccessibilityWindow(
                id: windowID(for: window),
                title: title(for: window) ?? "",
                frame: frame(for: window),
                isMinimized: (minimizedValue as? NSNumber)?.boolValue ?? false,
                isUtility: (subroleValue as? String) == utilitySubrole
            )
        }
    }
}
