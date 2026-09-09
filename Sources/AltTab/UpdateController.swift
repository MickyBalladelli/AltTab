import AppKit

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

    private let releasesURL = URL(string: "https://api.github.com/repos/MickyBalladelli/AltTab/releases/latest")!

    func checkForUpdates() {
        var request = URLRequest(url: releasesURL)
        request.setValue("AltTab", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            guard let data,
                  error == nil,
                  let release = try? JSONDecoder().decode(Release.self, from: data) else {
                self.presentError()
                return
            }
            self.present(release)
        }.resume()
    }

    private func present(_ release: Release) {
        DispatchQueue.main.async {
            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
            guard Self.compareVersions(latestVersion, currentVersion) == .orderedDescending else {
                self.showAlert(message: "AltTab is up to date", detail: "You are running AltTab \(currentVersion).")
                return
            }

            let downloadURL = release.assets.first { $0.name == "AltTab.dmg" }?.browserDownloadURL ?? release.htmlURL
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "AltTab \(latestVersion) is ready"
            alert.informativeText = "Download the signed and notarized release. macOS verifies the app before it opens."
            alert.addButton(withTitle: "Download update")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(downloadURL)
            }
        }
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
