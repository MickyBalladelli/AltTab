import AppKit
import CryptoKit

final class UpdateController {
    static let shared = UpdateController()

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private enum UpdateError: LocalizedError {
        case missingAssets
        case invalidChecksum
        case checksumMismatch
        case downloadFailed
        case verificationFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAssets:
                return "The release has no DMG and checksum assets."
            case .invalidChecksum:
                return "The release checksum file is invalid."
            case .checksumMismatch:
                return "The downloaded DMG checksum does not match the release checksum."
            case .downloadFailed:
                return "The update download failed."
            case .verificationFailed(let details):
                return details.isEmpty ? "macOS could not verify the update." : "macOS could not verify the update: " + details
            }
        }
    }

    private let releasesURL = URL(string: "https://api.github.com/repos/MickyBalladelli/AltTab/releases/latest")!
    private var isDownloading = false

    func checkForUpdates() {
        var request = URLRequest(url: releasesURL)
        request.setValue("AltTab", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            guard let data,
                  error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let release = try? JSONDecoder().decode(Release.self, from: data) else {
                self.presentError()
                return
            }
            self.present(release)
        }.resume()
    }

    private func present(_ release: Release) {
        DispatchQueue.main.async {
            let latestVersion = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
            guard Self.compareVersions(latestVersion, currentVersion) == .orderedDescending else {
                self.showAlert(message: "AltTab is up to date", detail: "You are running AltTab " + currentVersion + ".")
                return
            }

            guard SettingsStore.automaticUpdateDownloads else {
                self.presentManualDownload(release, version: latestVersion)
                return
            }

            guard let dmg = release.assets.first(where: { $0.name == "AltTab.dmg" }),
                  let checksum = release.assets.first(where: { $0.name == "AltTab.dmg.sha256" }) else {
                self.showAlert(message: "Automatic update unavailable", detail: UpdateError.missingAssets.localizedDescription)
                return
            }
            self.downloadAndVerify(version: latestVersion, dmg: dmg, checksum: checksum)
        }
    }

    private func presentManualDownload(_ release: Release, version: String) {
        let downloadURL = release.assets.first { $0.name == "AltTab.dmg" }?.browserDownloadURL ?? release.htmlURL
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AltTab " + version + " is ready"
        alert.informativeText = "Download the signed and notarized release. macOS verifies the app before it opens."
        alert.addButton(withTitle: "Download update")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(downloadURL)
        }
    }

    private func downloadAndVerify(version: String, dmg: Asset, checksum: Asset) {
        guard !isDownloading else { return }
        isDownloading = true
        let request = URLRequest(url: dmg.browserDownloadURL)
        URLSession.shared.downloadTask(with: request) { [weak self] temporaryURL, response, error in
            guard let self else { return }
            guard let temporaryURL,
                  error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                self.finishDownload(with: .failure(UpdateError.downloadFailed))
                return
            }

            do {
                let destination = try self.downloadDestination(for: version)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                self.fetchChecksum(from: checksum.browserDownloadURL, for: destination, version: version)
            } catch {
                self.finishDownload(with: .failure(error))
            }
        }.resume()
    }

    private func fetchChecksum(from url: URL, for dmgURL: URL, version: String) {
        var request = URLRequest(url: url)
        request.setValue("AltTab", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            guard let data,
                  error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let checksumText = String(data: data, encoding: .utf8),
                  let expectedChecksum = checksumText.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).first,
                  expectedChecksum.count == 64 else {
                self.finishDownload(with: .failure(UpdateError.invalidChecksum))
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.verifyChecksum(at: dmgURL, expected: String(expectedChecksum))
                    try Self.verifyRelease(at: dmgURL)
                    self.finishDownload(with: .success((version: version, url: dmgURL)))
                } catch {
                    self.finishDownload(with: .failure(error))
                }
            }
        }.resume()
    }

    private func downloadDestination(for version: String) throws -> URL {
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

        let safeVersion = version.map { character in
            character.isLetter || character.isNumber || character == "." || character == "-" ? String(character) : "-"
        }.joined()
        let baseURL = downloadsDirectory.appendingPathComponent("AltTab-" + safeVersion + ".dmg")
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return baseURL }
        return downloadsDirectory.appendingPathComponent("AltTab-" + safeVersion + "-" + String(UUID().uuidString.prefix(8)) + ".dmg")
    }

    private func finishDownload(with result: Result<(version: String, url: URL), Error>) {
        DispatchQueue.main.async {
            self.isDownloading = false
            switch result {
            case .success(let update):
                self.presentVerifiedUpdate(version: update.version, url: update.url)
            case .failure(let error):
                self.showAlert(message: "Automatic update stopped", detail: "The update was not opened. " + error.localizedDescription)
            }
        }
    }

    private func presentVerifiedUpdate(version: String, url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AltTab " + version + " is verified"
        alert.informativeText = "Checksum, Developer ID signature, and Apple notarization ticket passed. The DMG is saved at " + url.path + "."
        alert.addButton(withTitle: "Open update")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(url)
        }
    }

    private static func verifyChecksum(at url: URL, expected: String) throws {
        let data = try Data(contentsOf: url)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw UpdateError.checksumMismatch
        }
    }

    private static func verifyRelease(at url: URL) throws {
        try runProcess("/usr/bin/xcrun", arguments: ["stapler", "validate", url.path])

        let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("AltTab-update-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        var mounted = false
        defer {
            if mounted {
                _ = try? runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path])
            }
            try? FileManager.default.removeItem(at: mountPoint)
        }

        try runProcess("/usr/bin/hdiutil", arguments: ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint.path, url.path])
        mounted = true
        let appURL = mountPoint.appendingPathComponent("AltTab.app")
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw UpdateError.verificationFailed("AltTab.app was not found in the DMG.")
        }
        try runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])
        try runProcess("/usr/sbin/spctl", arguments: ["--assess", "--type", "execute", "--context", "context:primary-signature", appURL.path])
    }

    @discardableResult
    private static func runProcess(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
        } catch {
            throw UpdateError.verificationFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw UpdateError.verificationFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private func presentError() {
        DispatchQueue.main.async {
            self.showAlert(message: "Update check failed", detail: "Check your network connection or visit the AltTab release page later.")
        }
    }

    private func showAlert(message: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = numericComponents(lhs)
        let right = numericComponents(rhs)
        for index in 0..<max(left.count, right.count) {
            let leftComponent = index < left.count ? left[index] : 0
            let rightComponent = index < right.count ? right[index] : 0
            if leftComponent < rightComponent { return .orderedAscending }
            if leftComponent > rightComponent { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func numericComponents(_ version: String) -> [Int] {
        version.split(separator: ".").map { component in
            Int(component.prefix { $0.isNumber }) ?? 0
        }
    }
}
