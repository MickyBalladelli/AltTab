import AppKit

enum SwitcherContentMode: String, CaseIterable {
    case applications
    case windows
    case spaces
    case fullScreenApps
    case mixed

    var title: String {
        switch self {
        case .applications: return "Applications"
        case .windows: return "Windows"
        case .spaces: return "Spaces"
        case .fullScreenApps: return "Full-screen apps"
        case .mixed: return "Mixed"
        }
    }
}

enum ActivationShortcut: String, CaseIterable {
    case option = "option"
    case leftOption = "leftOption"
    case rightOption = "rightOption"
    case command = "command"
    case leftCommand = "leftCommand"
    case rightCommand = "rightCommand"

    var title: String {
        switch self {
        case .option: return "Option + Tab"
        case .leftOption: return "Left Option + Tab"
        case .rightOption: return "Right Option + Tab"
        case .command: return "Command + Tab"
        case .leftCommand: return "Left Command + Tab"
        case .rightCommand: return "Right Command + Tab"
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .option, .leftOption, .rightOption: return .option
        case .command, .leftCommand, .rightCommand: return .command
        }
    }

    var exactKeyCode: UInt16? {
        switch self {
        case .leftOption: return 58
        case .rightOption: return 61
        case .leftCommand: return 55
        case .rightCommand: return 54
        case .option, .command: return nil
        }
    }

    /// Command+Tab is reserved by macOS for the system app switcher and never
    /// reliably reaches a session event tap, so it cannot drive AltTab.
    var isSystemReserved: Bool {
        switch self {
        case .command, .leftCommand, .rightCommand: return true
        case .option, .leftOption, .rightOption: return false
        }
    }

    static let modifierKeyCodes: Set<UInt16> = [54, 55, 58, 61]

    func matches(flags: NSEvent.ModifierFlags, pressedKeyCodes: Set<UInt16>) -> Bool {
        guard flags.contains(modifierFlag) else { return false }
        guard let exactKeyCode else { return true }
        return pressedKeyCodes.contains(exactKeyCode)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((number >> 16) & 0xff) / 255,
            green: CGFloat((number >> 8) & 0xff) / 255,
            blue: CGFloat(number & 0xff) / 255,
            alpha: 1
        )
    }
}
