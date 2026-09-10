import AppKit
import Foundation

enum CrashDiagnostics {
    private static let folderName = "CrashDiagnostics"
    private static let reportPrefix = "AltTab-crash-"

    private static var directoryURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("AltTab", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static var reportCount: Int {
        let urls = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        return urls?.filter { $0.lastPathComponent.hasPrefix(reportPrefix) }.count ?? 0
    }

    static func install() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        NSSetUncaughtExceptionHandler(altTabUncaughtExceptionHandler)
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directoryURL)
    }

    fileprivate static func write(exception: NSException) {
        let date = ISO8601DateFormatter().string(from: Date())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let report = [
            "AltTab local crash report",
            "Date: " + date,
            "Version: " + version + " (build " + build + ")",
            "macOS: " + ProcessInfo.processInfo.operatingSystemVersionString,
            "Exception: " + exception.name.rawValue,
            "Reason: " + (exception.reason ?? "Unknown"),
            "",
            "Call stack:",
            exception.callStackSymbols.joined(separator: "\n")
        ].joined(separator: "\n")
        let fileName = reportPrefix + String(Date().timeIntervalSince1970) + "-" + UUID().uuidString + ".txt"
        let reportURL = directoryURL.appendingPathComponent(fileName)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)
    }
}

private func altTabUncaughtExceptionHandler(_ exception: NSException) {
    CrashDiagnostics.write(exception: exception)
}
