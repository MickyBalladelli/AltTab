import AppKit
import XCTest
@testable import AltTab

final class WindowFilteringTests: XCTestCase {
    private let defaultOptions = WindowFilterOptions(
        includeOffScreen: false,
        showMinimizedWindows: false,
        showUtilityWindows: false,
        onlyCurrentDisplay: false,
        excludedBundleIdentifiers: []
    )

    func testRejectsInvalidAndFilteredWindows() {
        XCTAssertFalse(WindowFilter.includes(candidate(layer: 1), options: defaultOptions))
        XCTAssertFalse(WindowFilter.includes(candidate(width: 80), options: defaultOptions))
        XCTAssertFalse(WindowFilter.includes(candidate(isUtility: true), options: defaultOptions))

        let excludedOptions = WindowFilterOptions(
            includeOffScreen: false,
            showMinimizedWindows: false,
            showUtilityWindows: true,
            onlyCurrentDisplay: false,
            excludedBundleIdentifiers: ["com.example.hidden"]
        )
        XCTAssertFalse(WindowFilter.includes(candidate(bundleIdentifier: "COM.EXAMPLE.HIDDEN"), options: excludedOptions))
    }

    func testHandlesDisplayAndVisibilityOptions() {
        XCTAssertFalse(WindowFilter.includes(candidate(isOnCurrentDisplay: false), options: WindowFilterOptions(
            includeOffScreen: false,
            showMinimizedWindows: false,
            showUtilityWindows: true,
            onlyCurrentDisplay: true,
            excludedBundleIdentifiers: []
        )))
        XCTAssertFalse(WindowFilter.includes(candidate(isOnScreen: false), options: defaultOptions))
        XCTAssertTrue(WindowFilter.includes(candidate(isOnScreen: false, isMinimized: true), options: WindowFilterOptions(
            includeOffScreen: false,
            showMinimizedWindows: true,
            showUtilityWindows: true,
            onlyCurrentDisplay: false,
            excludedBundleIdentifiers: []
        )))
        XCTAssertTrue(WindowFilter.includes(candidate(isOnScreen: false), options: WindowFilterOptions(
            includeOffScreen: true,
            showMinimizedWindows: false,
            showUtilityWindows: true,
            onlyCurrentDisplay: false,
            excludedBundleIdentifiers: []
        )))
    }

    private func candidate(
        bundleIdentifier: String = "com.example.app",
        layer: Int = 0,
        width: CGFloat = 800,
        height: CGFloat = 600,
        isOnScreen: Bool = true,
        isMinimized: Bool = false,
        isUtility: Bool = false,
        isOnCurrentDisplay: Bool = true
    ) -> WindowFilterCandidate {
        WindowFilterCandidate(
            bundleIdentifier: bundleIdentifier,
            layer: layer,
            width: width,
            height: height,
            isOnScreen: isOnScreen,
            isMinimized: isMinimized,
            isUtility: isUtility,
            isOnCurrentDisplay: isOnCurrentDisplay
        )
    }
}

final class MRUStoreTests: XCTestCase {
    func testSavedIdentifiersRestoreOrderAndIgnoreMissingWindows() {
        let items = [
            makeItem(identifier: "window:first", title: "First", windowID: 1),
            makeItem(identifier: "window:second", title: "Second", windowID: 2),
            makeItem(identifier: "window:third", title: "Third", windowID: 3)
        ]

        let ordered = MRUStore.ordered(items, savedIdentifiers: ["window:third", "window:missing", "window:first"])

        XCTAssertEqual(ordered.map(\.identifier), ["window:third", "window:first", "window:second"])
    }
}

final class ShortcutStoreTests: XCTestCase {
    private let shortcutKeyPrefix = "AltTab.quickSlot."
    private var originalValues: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for slot in 1...12 {
            for suffix in ["", ".keyCode", ".modifiers"] {
                let key = shortcutKeyPrefix + "\(slot)" + suffix
                if let value = defaults.object(forKey: key) {
                    originalValues[key] = value
                }
            }
            ShortcutStore.clear(slot: slot)
        }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for slot in 1...12 {
            ShortcutStore.clear(slot: slot)
        }
        for (key, value) in originalValues {
            defaults.set(value, forKey: key)
        }
        super.tearDown()
    }

    func testDefaultFKeyMappingCoversF1ThroughF12() {
        let expected: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

        XCTAssertEqual((1...12).compactMap(ShortcutStore.defaultKeyCode), expected)
        XCTAssertEqual((1...12).map { ShortcutStore.trigger(for: $0).keyCode }, expected)
    }

    func testCustomTriggerAndBundlePersistAndMatchAnEvent() {
        ShortcutStore.setBundleIdentifier("com.example.TestApp", for: 1)
        ShortcutStore.setTrigger(keyCode: 97, modifiers: NSEvent.ModifierFlags.command.rawValue, for: 1)

        XCTAssertEqual(ShortcutStore.bundleIdentifier(for: 1), "com.example.TestApp")
        XCTAssertEqual(ShortcutStore.trigger(for: 1).keyCode, 97)
        XCTAssertEqual(ShortcutStore.trigger(for: 1).modifiers, NSEvent.ModifierFlags.command.rawValue)

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 97
        )

        XCTAssertEqual(event.flatMap(ShortcutStore.slot), 1)
    }

    func testImportReplacesExistingBindingsWithoutSwapConflicts() throws {
        ShortcutStore.setTrigger(keyCode: 97, modifiers: NSEvent.ModifierFlags.command.rawValue, for: 1)
        ShortcutStore.setBundleIdentifier("com.example.First", for: 1)
        ShortcutStore.setTrigger(keyCode: 98, modifiers: NSEvent.ModifierFlags.command.rawValue, for: 2)
        ShortcutStore.setBundleIdentifier("com.example.Second", for: 2)
        let exported = try ShortcutStore.exportBindings()

        ShortcutStore.clear(slot: 1)
        ShortcutStore.clear(slot: 2)
        ShortcutStore.setTrigger(keyCode: 98, modifiers: NSEvent.ModifierFlags.command.rawValue, for: 1)
        ShortcutStore.setBundleIdentifier("com.example.First", for: 1)
        ShortcutStore.setTrigger(keyCode: 97, modifiers: NSEvent.ModifierFlags.command.rawValue, for: 2)
        ShortcutStore.setBundleIdentifier("com.example.Second", for: 2)

        XCTAssertNoThrow(try ShortcutStore.importBindings(exported))
        XCTAssertEqual(ShortcutStore.trigger(for: 1).keyCode, 97)
        XCTAssertEqual(ShortcutStore.trigger(for: 2).keyCode, 98)
        XCTAssertEqual(ShortcutStore.bundleIdentifier(for: 1), "com.example.First")
        XCTAssertEqual(ShortcutStore.bundleIdentifier(for: 2), "com.example.Second")
    }

    func testInvalidImportDoesNotPartiallyReplaceBindings() throws {
        ShortcutStore.setTrigger(keyCode: 97, modifiers: NSEvent.ModifierFlags.command.rawValue, for: 1)
        ShortcutStore.setBundleIdentifier("com.example.Original", for: 1)
        let command = NSEvent.ModifierFlags.command.rawValue
        let invalidImport = Data("""
        [
          {"slot": 1, "bundleIdentifier": "com.example.Replacement", "keyCode": 98, "modifiers": \(command)},
          {"slot": 13, "bundleIdentifier": "com.example.Invalid", "keyCode": 99, "modifiers": \(command)}
        ]
        """.utf8)

        XCTAssertThrowsError(try ShortcutStore.importBindings(invalidImport))
        XCTAssertEqual(ShortcutStore.trigger(for: 1).keyCode, 97)
        XCTAssertEqual(ShortcutStore.bundleIdentifier(for: 1), "com.example.Original")
    }
}

final class SettingsStoreTests: XCTestCase {
    override func tearDown() {
        for action in WindowAction.allCases {
            SettingsStore.resetWindowActionShortcut(for: action)
        }
        super.tearDown()
    }

    func testCommandTabIsTheDefaultActivationShortcut() {
        let defaults = UserDefaults.standard
        let originalValue = defaults.object(forKey: SettingsStore.activationShortcutKey)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: SettingsStore.activationShortcutKey)
            } else {
                defaults.removeObject(forKey: SettingsStore.activationShortcutKey)
            }
        }

        defaults.removeObject(forKey: SettingsStore.activationShortcutKey)
        SettingsStore.registerDefaults()
        XCTAssertEqual(SettingsStore.activationShortcut, .command)
    }

    func testReplacingWindowActionShortcutsSupportsSwappedBindings() throws {
        let minimize = WindowActionShortcut.defaultShortcut(for: .minimize)
        let close = WindowActionShortcut.defaultShortcut(for: .close)
        var shortcuts = Dictionary(uniqueKeysWithValues: WindowAction.allCases.map {
            ($0.rawValue, WindowActionShortcut.defaultShortcut(for: $0))
        })
        shortcuts[WindowAction.minimize.rawValue] = close
        shortcuts[WindowAction.close.rawValue] = minimize

        XCTAssertNoThrow(try SettingsStore.replaceWindowActionShortcuts(shortcuts))
        XCTAssertEqual(SettingsStore.windowActionShortcut(for: .minimize), close)
        XCTAssertEqual(SettingsStore.windowActionShortcut(for: .close), minimize)
    }
}

final class SwitcherUITests: XCTestCase {
    func testCyclingCancelingAndCommitting() {
        var state = SwitcherState()
        let items = [
            makeItem(identifier: "window:one", title: "One", windowID: 1),
            makeItem(identifier: "window:two", title: "Two", windowID: 2),
            makeItem(identifier: "window:three", title: "Three", windowID: 3)
        ]

        XCTAssertTrue(state.begin(items: items))
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertTrue(state.advance())
        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertTrue(state.previous())
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertTrue(state.select(index: 2))

        let committed = state.commit()
        XCTAssertEqual(committed?.identifier, "window:three")
        XCTAssertFalse(state.isVisible)

        XCTAssertTrue(state.begin(items: items))
        state.cancel()
        XCTAssertFalse(state.isVisible)
    }

    func testSearchKeepsSameAppWindowsDistinct() {
        var state = SwitcherState()
        let first = makeItem(identifier: "window:one", title: "Document One", windowID: 1)
        let second = makeItem(identifier: "window:two", title: "Document Two", windowID: 2)
        XCTAssertEqual(first.app?.processIdentifier, second.app?.processIdentifier)

        XCTAssertTrue(state.begin(items: [first, second]))
        XCTAssertTrue(state.appendSearchText("Document Two"))
        XCTAssertEqual(state.items.map(\.identifier), ["window:two"])
        XCTAssertEqual(state.commit()?.window?.windowID, 2)
    }

    func testSwitcherViewReflectsSelectedWindow() {
        let view = SwitcherView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
        view.items = [
            makeItem(identifier: "window:one", title: "One", windowID: 1),
            makeItem(identifier: "window:two", title: "Two", windowID: 2)
        ]
        view.selectedIndex = 1

        XCTAssertEqual(view.items[view.selectedIndex].window?.windowID, 2)
        XCTAssertGreaterThan(SwitcherView.preferredSize(for: view.items.count).height, 0)
    }

    func testWindowRefreshPreservesTheSelectedItemsMode() {
        let space = makeItem(identifier: "space:2", title: "Space 2", windowID: 2, kind: .spaces)
        let fullScreenApp = makeItem(identifier: "fullscreen:app", title: "Full screen", windowID: 3, kind: .fullScreenApps)

        XCTAssertEqual(SwitcherController.refreshMode(for: space), .spaces)
        XCTAssertEqual(SwitcherController.refreshMode(for: fullScreenApp), .fullScreenApps)
    }
}

private func makeItem(
    identifier: String,
    title: String,
    windowID: CGWindowID,
    kind: SwitcherContentMode = .windows
) -> SwitcherItem {
    let app = NSRunningApplication.current
    let image = NSImage(size: NSSize(width: 16, height: 16))
    let window = WindowItem(
        windowID: windowID,
        app: app,
        title: title,
        icon: image,
        thumbnail: nil,
        isMinimized: false,
        frame: NSRect(x: 0, y: 0, width: 800, height: 600),
        workspaceID: nil,
        isFullScreen: false
    )
    return SwitcherItem(
        identifier: identifier,
        title: title,
        subtitle: app.localizedName ?? "Test app",
        app: app,
        window: window,
        icon: image,
        kind: kind
    )
}
