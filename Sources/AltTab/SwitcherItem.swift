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
        window?.thumbnail
    }

    func activate() {
        if let window {
            window.activate()
        } else {
            app?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }
}
