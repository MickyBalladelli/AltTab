import AppKit
import ApplicationServices

enum WindowAction: String, CaseIterable, Equatable, Hashable {
    case minimize
    case close
    case hideApp
    case moveToDisplay
    case moveToSpace

    var title: String {
        switch self {
        case .minimize: return "Minimize window"
        case .close: return "Close window"
        case .hideApp: return "Hide app"
        case .moveToDisplay: return "Move window to next display"
        case .moveToSpace: return "Move window to next Space"
        }
    }
}

struct WindowActionShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifierRawValue: UInt

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    var displayName: String {
        let modifierNames: [(NSEvent.ModifierFlags, String)] = [(.command, "⌘"), (.option, "⌥"), (.control, "⌃"), (.shift, "⇧")]
        let modifiers = modifierNames.compactMap { modifier, name in
            modifierRawValue & modifier.rawValue != 0 ? name : nil
        }.joined()
        return modifiers + Self.keyName(for: keyCode)
    }

    func matches(_ event: NSEvent) -> Bool {
        let eventModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
        return keyCode == event.keyCode && modifierRawValue == eventModifiers
    }

    static func defaultShortcut(for action: WindowAction) -> WindowActionShortcut {
        switch action {
        case .minimize:
            return WindowActionShortcut(keyCode: 46, modifierRawValue: NSEvent.ModifierFlags.command.rawValue)
        case .close:
            return WindowActionShortcut(keyCode: 13, modifierRawValue: NSEvent.ModifierFlags.command.rawValue)
        case .hideApp:
            return WindowActionShortcut(keyCode: 4, modifierRawValue: NSEvent.ModifierFlags.command.rawValue)
        case .moveToDisplay:
            return WindowActionShortcut(keyCode: 124, modifierRawValue: NSEvent.ModifierFlags([.control, .option]).rawValue)
        case .moveToSpace:
            return WindowActionShortcut(keyCode: 124, modifierRawValue: NSEvent.ModifierFlags([.control, .shift]).rawValue)
        }
    }

    private static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 4: return "H"
        case 13: return "W"
        case 46: return "M"
        case 48: return "Tab"
        case 53: return "Escape"
        case 36, 76: return "Return"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return "Key \(keyCode)"
        }
    }
}

enum WindowActionService {
    @discardableResult
    static func perform(_ action: WindowAction, on item: SwitcherItem) -> Bool {
        let succeeded: Bool
        switch action {
        case .hideApp:
            succeeded = item.app?.hide() ?? false
        case .minimize:
            guard let window = item.window, let element = window.accessibilityElement() else {
                return reportFailure(action)
            }
            succeeded = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
        case .close:
            guard let window = item.window, let element = window.accessibilityElement() else {
                return reportFailure(action)
            }
            var closeButton: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &closeButton) == .success,
                  let closeButton,
                  CFGetTypeID(closeButton) == AXUIElementGetTypeID() else {
                return reportFailure(action)
            }
            let button = closeButton as! AXUIElement
            succeeded = AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        case .moveToDisplay:
            succeeded = moveToNextDisplay(item)
        case .moveToSpace:
            succeeded = moveToNextSpace(item)
        }
        if !succeeded {
            return reportFailure(action)
        }
        return true
    }

    @discardableResult
    static func performWithConfirmation(_ action: WindowAction, on item: SwitcherItem) -> Bool {
        if action == .close {
            let alert = NSAlert()
            alert.messageText = "Close window?"
            alert.informativeText = "Close \(item.title)? Any unsaved changes may be lost."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        return perform(action, on: item)
    }

    static func nextDisplayName(for item: SwitcherItem) -> String? {
        guard let transition = displayTransition(for: item) else { return nil }
        let target = transition.screens[transition.targetIndex]
        return target.localizedName.isEmpty ? "Display \(transition.targetIndex + 1)" : target.localizedName
    }

    private static func moveToNextDisplay(_ item: SwitcherItem) -> Bool {
        guard let transition = displayTransition(for: item) else { return false }
        let window = transition.window
        let element = transition.element
        let target = transition.screens[transition.targetIndex]
        guard let displayID = target.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }

        var targetBounds = CGDisplayBounds(displayID)
        targetBounds.origin.x += (targetBounds.width - window.frame.width) / 2
        targetBounds.origin.y += (targetBounds.height - window.frame.height) / 2
        var point = targetBounds.origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    private static func displayTransition(for item: SwitcherItem) -> (window: WindowItem, element: AXUIElement, screens: [NSScreen], targetIndex: Int)? {
        guard let window = item.window,
              let element = window.accessibilityElement() else { return nil }

        let screens = NSScreen.screens
        guard screens.count > 1 else { return nil }
        let currentIndex = screens.firstIndex { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayBounds(displayID).intersects(window.frame)
        } ?? 0
        return (window, element, screens, (currentIndex + 1) % screens.count)
    }

    private static func moveToNextSpace(_ item: SwitcherItem) -> Bool {
        guard let window = item.window else { return false }
        guard window.activate() else { return false }
        return postSpaceMoveShortcut()
    }

    private static func postSpaceMoveShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 124, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 124, keyDown: false) else { return false }
        let flags: CGEventFlags = [.maskControl, .maskShift]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func reportFailure(_ action: WindowAction) -> Bool {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Could not \(action.title.lowercased())"
            alert.informativeText = "macOS did not allow AltTab to complete this action. Check Accessibility permission and try again."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        return false
    }
}
