import AppKit
import ApplicationServices

struct WindowCatalogProfile: Equatable {
    let elapsedMilliseconds: Double
    let windowCount: Int
    let iconCacheHits: Int
    let iconCacheMisses: Int
    let thumbnailCacheHits: Int
    let thumbnailCacheMisses: Int
}

struct WindowItem {
    let windowID: CGWindowID
    let app: NSRunningApplication
    let title: String
    let icon: NSImage
    let thumbnail: NSImage?
    let isMinimized: Bool
    let frame: CGRect
    let displayName: String
    let workspaceID: Int?
    let isFullScreen: Bool

    init(
        windowID: CGWindowID,
        app: NSRunningApplication,
        title: String,
        icon: NSImage,
        thumbnail: NSImage?,
        isMinimized: Bool,
        frame: CGRect,
        displayName: String = "Display",
        workspaceID: Int?,
        isFullScreen: Bool
    ) {
        self.windowID = windowID
        self.app = app
        self.title = title
        self.icon = icon
        self.thumbnail = thumbnail
        self.isMinimized = isMinimized
        self.frame = frame
        self.displayName = displayName
        self.workspaceID = workspaceID
        self.isFullScreen = isFullScreen
    }

    var stableIdentifier: String {
        let bundleIdentifier = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "|", with: "/")
        let x = Int(frame.origin.x.rounded())
        let y = Int(frame.origin.y.rounded())
        let width = Int(frame.width.rounded())
        let height = Int(frame.height.rounded())
        return "window:\(bundleIdentifier):\(safeTitle):\(x):\(y):\(width):\(height)"
    }

    func accessibilityElement() -> AXUIElement? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }

        return windows.first { window in
            WindowCatalog.windowID(for: window) == windowID
        } ?? windows.first { window in
            guard let candidateFrame = WindowCatalog.frame(for: window) else { return false }
            return WindowCatalog.framesMatch(candidateFrame, frame)
        } ?? windows.first { window in
            WindowCatalog.title(for: window) == title
        }
    }

    @discardableResult
    func activate() -> Bool {
        _ = app.activate(options: [.activateIgnoringOtherApps])
        guard let window = accessibilityElement() else { return false }
        if isMinimized {
            guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else { return false }
        }
        return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
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

    private struct CatalogCacheKey: Equatable {
        let mode: SwitcherContentMode
        let showMinimizedWindows: Bool
        let showUtilityWindows: Bool
        let onlyCurrentDisplay: Bool
        let excludedBundleIdentifiers: String
        let thumbnailSize: Int
    }

    private struct CatalogCacheEntry {
        let key: CatalogCacheKey
        let items: [SwitcherItem]
        let createdAt: CFAbsoluteTime
    }

    private struct DisplaySnapshot {
        let displays: [DisplayInfo]
        let currentScreenBounds: CGRect?
    }

    private struct DisplayInfo {
        let name: String
        let bounds: CGRect
    }

    private struct CatalogSettings {
        let showMinimizedWindows: Bool
        let showUtilityWindows: Bool
        let onlyCurrentDisplay: Bool
        let excludedBundleIdentifiers: Set<String>
        let thumbnailSize: Int
    }

    private final class ThumbnailCacheEntry {
        let image: NSImage
        let createdAt: CFAbsoluteTime

        init(image: NSImage, createdAt: CFAbsoluteTime) {
            self.image = image
            self.createdAt = createdAt
        }
    }

    private static let windowNumberAttribute = "AXWindowNumber" as CFString
    private static let utilitySubrole = "AXUtilityWindow"
    private static let workspaceKey = "kCGWindowWorkspace"
    private static let loadQueue = DispatchQueue(label: "com.mickyballadelli.alttab.window-catalog", qos: .userInitiated)
    private static let loadLock = NSLock()
    private static var loadWorkItem: DispatchWorkItem?
    private static var loadGeneration = 0
    private static var cachedItems: CatalogCacheEntry?
    private static let refreshDebounce: TimeInterval = 0.06
    private static let cacheLifetime: TimeInterval = 0.2
    private static let iconCacheLock = NSLock()
    private static var iconCache: [String: NSImage] = [:]
    private static let thumbnailCacheLock = NSLock()
    private static let thumbnailCache: NSCache<NSString, ThumbnailCacheEntry> = {
        let cache = NSCache<NSString, ThumbnailCacheEntry>()
        cache.countLimit = 64
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    private static var thumbnailCacheSize: Int?
    private(set) static var lastProfile = WindowCatalogProfile(
        elapsedMilliseconds: 0,
        windowCount: 0,
        iconCacheHits: 0,
        iconCacheMisses: 0,
        thumbnailCacheHits: 0,
        thumbnailCacheMisses: 0
    )

    static func items(for mode: SwitcherContentMode) -> [SwitcherItem] {
        SettingsStore.registerDefaults()
        return items(
            for: mode,
            settings: catalogSettings(),
            displaySnapshot: displaySnapshot()
        )
    }

    private static func items(
        for mode: SwitcherContentMode,
        settings: CatalogSettings,
        displaySnapshot: DisplaySnapshot
    ) -> [SwitcherItem] {
        switch mode {
        case .applications:
            return applicationItems(from: visibleWindows(settings: settings, displaySnapshot: displaySnapshot))
        case .windows:
            return visibleWindows(settings: settings, displaySnapshot: displaySnapshot).map { windowItem($0) }
        case .spaces:
            return spaceItems(from: allWindows(settings: settings, displaySnapshot: displaySnapshot))
        case .fullScreenApps:
            return fullScreenAppItems(from: visibleWindows(settings: settings, displaySnapshot: displaySnapshot))
        case .mixed:
            let windows = visibleWindows(settings: settings, displaySnapshot: displaySnapshot)
            return applicationItems(from: windows) + windows.map { windowItem($0) } + spaceItems(from: allWindows(settings: settings, displaySnapshot: displaySnapshot))
        }
    }

    static func loadItems(for mode: SwitcherContentMode, completion: @escaping ([SwitcherItem]) -> Void) {
        SettingsStore.registerDefaults()
        let settings = catalogSettings()
        let key = cacheKey(for: mode, settings: settings)
        let displaySnapshot = displaySnapshot()

        loadLock.lock()
        loadGeneration += 1
        let generation = loadGeneration
        loadWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            loadLock.lock()
            guard generation == loadGeneration else {
                loadLock.unlock()
                return
            }
            if let cachedItems,
               cachedItems.key == key,
               CFAbsoluteTimeGetCurrent() - cachedItems.createdAt < cacheLifetime {
                let items = cachedItems.items
                loadLock.unlock()
                deliver(items, generation: generation, completion: completion)
                return
            }
            loadLock.unlock()

            let items = self.items(for: mode, settings: settings, displaySnapshot: displaySnapshot)

            loadLock.lock()
            guard generation == loadGeneration else {
                loadLock.unlock()
                return
            }
            cachedItems = CatalogCacheEntry(key: key, items: items, createdAt: CFAbsoluteTimeGetCurrent())
            loadLock.unlock()
            deliver(items, generation: generation, completion: completion)
        }
        loadWorkItem = workItem
        loadLock.unlock()
        loadQueue.asyncAfter(deadline: .now() + refreshDebounce, execute: workItem)
    }

    static func resetCaches() {
        loadLock.lock()
        loadGeneration += 1
        loadWorkItem?.cancel()
        loadWorkItem = nil
        cachedItems = nil
        loadLock.unlock()

        iconCacheLock.lock()
        iconCache.removeAll()
        iconCacheLock.unlock()

        thumbnailCacheLock.lock()
        thumbnailCache.removeAllObjects()
        thumbnailCacheSize = nil
        thumbnailCacheLock.unlock()
    }

    private static func catalogSettings() -> CatalogSettings {
        CatalogSettings(
            showMinimizedWindows: SettingsStore.showMinimizedWindows,
            showUtilityWindows: SettingsStore.showUtilityWindows,
            onlyCurrentDisplay: SettingsStore.onlyCurrentDisplay,
            excludedBundleIdentifiers: SettingsStore.excludedBundleIdentifiers,
            thumbnailSize: Int(SettingsStore.thumbnailSize.rounded())
        )
    }

    private static func cacheKey(for mode: SwitcherContentMode, settings: CatalogSettings) -> CatalogCacheKey {
        CatalogCacheKey(
            mode: mode,
            showMinimizedWindows: settings.showMinimizedWindows,
            showUtilityWindows: settings.showUtilityWindows,
            onlyCurrentDisplay: settings.onlyCurrentDisplay,
            excludedBundleIdentifiers: settings.excludedBundleIdentifiers.sorted().joined(separator: "|"),
            thumbnailSize: settings.thumbnailSize
        )
    }

    private static func deliver(
        _ items: [SwitcherItem],
        generation: Int,
        completion: @escaping ([SwitcherItem]) -> Void
    ) {
        DispatchQueue.main.async {
            loadLock.lock()
            let isCurrent = generation == loadGeneration
            loadLock.unlock()
            guard isCurrent else { return }
            completion(items)
        }
    }

    private static func applicationItems(from windows: [WindowItem]) -> [SwitcherItem] {
        var seen = Set<String>()
        return windows.compactMap { window in
            let identifier = window.app.bundleIdentifier ?? "pid:\(window.app.processIdentifier)"
            guard seen.insert(identifier).inserted else { return nil }
            return SwitcherItem(
                identifier: "app:\(identifier)",
                title: window.app.localizedName ?? "Application",
                subtitle: "Application",
                app: window.app,
                window: nil,
                icon: window.icon,
                kind: .applications
            )
        }
    }

    private static func windowItem(_ window: WindowItem) -> SwitcherItem {
        let appName = window.app.localizedName ?? "Window"
        return SwitcherItem(
            identifier: window.stableIdentifier,
            title: window.title,
            subtitle: "\(appName) · \(window.displayName)",
            app: window.app,
            window: window,
            icon: window.icon,
            kind: .windows
        )
    }

    private static func fullScreenAppItems(from windows: [WindowItem]) -> [SwitcherItem] {
        var seen = Set<String>()
        return windows.filter { $0.isFullScreen }.compactMap { window in
            let identifier = window.app.bundleIdentifier ?? "pid:\(window.app.processIdentifier)"
            guard seen.insert(identifier).inserted else { return nil }
            return SwitcherItem(
                identifier: "fullscreen:\(identifier)",
                title: window.app.localizedName ?? "Full-screen app",
                subtitle: "Full-screen app",
                app: window.app,
                window: window,
                icon: window.icon,
                kind: .fullScreenApps
            )
        }
    }

    private static func spaceItems(from windows: [WindowItem]) -> [SwitcherItem] {
        var representatives: [Int: WindowItem] = [:]
        for window in windows {
            guard let workspaceID = window.workspaceID else { continue }
            if representatives[workspaceID] == nil {
                representatives[workspaceID] = window
            }
        }

        guard !representatives.isEmpty else {
            guard let window = windows.first else { return [] }
            return [SwitcherItem(
                identifier: "space:current",
                title: "Current Space",
                subtitle: window.displayName,
                app: window.app,
                window: window,
                icon: NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Space") ?? window.icon,
                kind: .spaces
            )]
        }

        return representatives.keys.sorted().enumerated().compactMap { index, workspaceID in
            guard let window = representatives[workspaceID] else { return nil }
            return SwitcherItem(
                identifier: "space:\(workspaceID)",
                title: "Space \(index + 1) · \(window.displayName)",
                subtitle: "Workspace \(workspaceID)",
                app: window.app,
                window: window,
                icon: NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Space") ?? window.icon,
                kind: .spaces
            )
        }
    }

    private static func visibleWindows(settings: CatalogSettings, displaySnapshot: DisplaySnapshot) -> [WindowItem] {
        enumerateWindows(includeOffScreen: false, settings: settings, displaySnapshot: displaySnapshot)
    }

    private static func allWindows(settings: CatalogSettings, displaySnapshot: DisplaySnapshot) -> [WindowItem] {
        enumerateWindows(includeOffScreen: true, settings: settings, displaySnapshot: displaySnapshot)
    }

    private static func enumerateWindows(
        includeOffScreen: Bool,
        settings: CatalogSettings,
        displaySnapshot: DisplaySnapshot
    ) -> [WindowItem] {
        let listOptions: CGWindowListOption = includeOffScreen || settings.showMinimizedWindows
            ? [.optionAll, .excludeDesktopElements]
            : [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(listOptions, kCGNullWindowID) as? [[String: Any]] else { return [] }

        var accessibilityCache: [pid_t: [AccessibilityWindow]] = [:]
        var seenWindowIDs = Set<CGWindowID>()
        var iconCacheHits = 0
        var iconCacheMisses = 0
        var thumbnailCacheHits = 0
        var thumbnailCacheMisses = 0
        let startedAt = CFAbsoluteTimeGetCurrent()

        let result: [WindowItem] = list.compactMap { (info: [String: Any]) -> WindowItem? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let app = NSRunningApplication(processIdentifier: ownerPID),
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  seenWindowIDs.insert(windowID).inserted else { return nil }

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
            let isOnCurrentDisplay = isOnCurrentDisplay(windowFrame, currentScreenBounds: displaySnapshot.currentScreenBounds)
            let filterOptions = WindowFilterOptions(
                includeOffScreen: includeOffScreen,
                showMinimizedWindows: settings.showMinimizedWindows,
                showUtilityWindows: settings.showUtilityWindows,
                onlyCurrentDisplay: settings.onlyCurrentDisplay,
                excludedBundleIdentifiers: settings.excludedBundleIdentifiers
            )
            let candidate = WindowFilterCandidate(
                bundleIdentifier: app.bundleIdentifier ?? "",
                layer: layer,
                width: windowFrame.width,
                height: windowFrame.height,
                isOnScreen: isOnScreen,
                isMinimized: isMinimized,
                isUtility: accessibilityWindow?.isUtility ?? false,
                isOnCurrentDisplay: isOnCurrentDisplay
            )
            guard WindowFilter.includes(candidate, options: filterOptions) else { return nil }

            let title = info[kCGWindowName as String] as? String ?? app.localizedName ?? "Window"
            let resolvedTitle = title.isEmpty ? (app.localizedName ?? "Window") : title
            let cachedIcon = icon(for: app)
            if cachedIcon.wasCached {
                iconCacheHits += 1
            } else {
                iconCacheMisses += 1
            }
            let cachedThumbnail = thumbnail(
                for: windowID,
                frame: windowFrame,
                requestedSize: settings.thumbnailSize
            )
            if cachedThumbnail.wasCached {
                thumbnailCacheHits += 1
            } else {
                thumbnailCacheMisses += 1
            }
            let isFullScreen = displaySnapshot.displays.contains { display in
                abs(windowFrame.width - display.bounds.width) < 4 && abs(windowFrame.height - display.bounds.height) < 4
            }
            return WindowItem(
                windowID: windowID,
                app: app,
                title: resolvedTitle,
                icon: cachedIcon.image,
                thumbnail: cachedThumbnail.image,
                isMinimized: isMinimized,
                frame: windowFrame,
                displayName: displayName(for: windowFrame, in: displaySnapshot.displays),
                workspaceID: (info[workspaceKey] as? NSNumber)?.intValue,
                isFullScreen: isFullScreen
            )
        }
        lastProfile = WindowCatalogProfile(
            elapsedMilliseconds: (CFAbsoluteTimeGetCurrent() - startedAt) * 1000,
            windowCount: result.count,
            iconCacheHits: iconCacheHits,
            iconCacheMisses: iconCacheMisses,
            thumbnailCacheHits: thumbnailCacheHits,
            thumbnailCacheMisses: thumbnailCacheMisses
        )
        return result
    }

    private static func icon(for app: NSRunningApplication) -> (image: NSImage, wasCached: Bool) {
        let key = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        iconCacheLock.lock()
        if let cached = iconCache[key] {
            iconCacheLock.unlock()
            return (cached, true)
        }
        let image = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
        iconCache[key] = image
        iconCacheLock.unlock()
        return (image, false)
    }

    private static func thumbnail(
        for windowID: CGWindowID,
        frame: CGRect,
        requestedSize: Int
    ) -> (image: NSImage?, wasCached: Bool) {
        let size = max(24, requestedSize)
        let key = [
            String(windowID),
            String(Int(frame.origin.x.rounded())),
            String(Int(frame.origin.y.rounded())),
            String(Int(frame.width.rounded())),
            String(Int(frame.height.rounded())),
            String(size)
        ].joined(separator: ":") as NSString

        thumbnailCacheLock.lock()
        if thumbnailCacheSize != size {
            thumbnailCache.removeAllObjects()
            thumbnailCacheSize = size
        }
        if let cached = thumbnailCache.object(forKey: key),
           CFAbsoluteTimeGetCurrent() - cached.createdAt < 1.0 {
            thumbnailCacheLock.unlock()
            return (cached.image, true)
        }
        thumbnailCache.removeObject(forKey: key)
        thumbnailCacheLock.unlock()

        guard let image = CGWindowListCreateImage(
            .null,
            [.optionIncludingWindow],
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ), let thumbnail = downsample(image, to: size) else {
            return (nil, false)
        }

        thumbnailCacheLock.lock()
        thumbnailCache.setObject(
            ThumbnailCacheEntry(image: thumbnail, createdAt: CFAbsoluteTimeGetCurrent()),
            forKey: key,
            cost: size * size * 4
        )
        thumbnailCacheLock.unlock()
        return (thumbnail, false)
    }

    private static func downsample(_ image: CGImage, to size: Int) -> NSImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let resizedImage = context.makeImage() else { return nil }
        return NSImage(cgImage: resizedImage, size: NSSize(width: size, height: size))
    }

    private static func displaySnapshot() -> DisplaySnapshot {
        let screens = NSScreen.screens
        let displays = screens.enumerated().map { index, screen in
            DisplayInfo(
                name: screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName,
                bounds: screen.frame
            )
        }
        return DisplaySnapshot(displays: displays, currentScreenBounds: NSScreen.main?.frame)
    }

    private static func displayName(for windowFrame: CGRect, in displays: [DisplayInfo]) -> String {
        displays.first { $0.bounds.intersects(windowFrame) }?.name ?? "Other display"
    }

    private static func isOnCurrentDisplay(_ windowFrame: CGRect, currentScreenBounds: CGRect?) -> Bool {
        guard let currentScreenBounds else { return true }
        return windowFrame.intersects(currentScreenBounds)
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
