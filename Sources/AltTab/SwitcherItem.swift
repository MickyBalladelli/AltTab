import AppKit

struct SwitcherItem {
    let identifier: String
    let title: String
    let subtitle: String
    let app: NSRunningApplication?
    let window: WindowItem?
    let icon: NSImage
    let kind: SwitcherContentMode

    var thumbnail: NSImage? {
        switch kind {
        case .windows, .fullScreenApps:
            return window?.thumbnail
        case .applications, .spaces, .mixed:
            return nil
        }
    }

    @discardableResult
    func activate() -> Bool {
        if let window {
            return window.activate()
        } else {
            return app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) ?? false
        }
    }
}
