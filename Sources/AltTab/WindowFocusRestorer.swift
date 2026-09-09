import AppKit

final class WindowFocusRestorer {
    private var previousApplication: NSRunningApplication?

    func capture() {
        let currentProcessIdentifier = NSRunningApplication.current.processIdentifier
        previousApplication = NSWorkspace.shared.frontmostApplication?.processIdentifier == currentProcessIdentifier
            ? nil
            : NSWorkspace.shared.frontmostApplication
    }

    func restore() {
        previousApplication?.activate(options: [.activateIgnoringOtherApps])
        previousApplication = nil
    }
}
