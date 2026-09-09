import AppKit

if CommandLine.arguments.contains("--benchmark-window-catalog") {
    WindowCatalogBenchmark.run()
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
