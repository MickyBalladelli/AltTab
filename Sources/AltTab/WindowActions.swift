import AppKit
import ApplicationServices

enum WindowAction: CaseIterable, Equatable {
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
                  let button = closeButton as? AXUIElement else {
                return reportFailure(action)
            }
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

    private static func moveToNextDisplay(_ item: SwitcherItem) -> Bool {
        guard let window = item.window,
              let element = window.accessibilityElement(),
              NSScreen.screens.count > 1 else { return false }

        let screens = NSScreen.screens
        let currentIndex = screens.firstIndex { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayBounds(displayID).intersects(window.frame)
        } ?? 0
        let targetIndex = (currentIndex + 1) % screens.count
        guard let displayID = screens[targetIndex].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }

        var targetBounds = CGDisplayBounds(displayID)
        targetBounds.origin.x += (targetBounds.width - window.frame.width) / 2
        targetBounds.origin.y += (targetBounds.height - window.frame.height) / 2
        var point = targetBounds.origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
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
