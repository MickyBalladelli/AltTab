import AppKit
import ApplicationServices

enum AccessibilityController {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermissionPrompt() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

final class AccessibilityOnboardingController {
    private var permissionTimer: Timer?

    func presentIfNeeded() {
        guard !AccessibilityController.isTrusted else { return }
        AccessibilityController.requestPermissionPrompt()
        DispatchQueue.main.async { [weak self] in
            self?.showAlertIfNeeded()
        }
    }

    func showAlertIfNeeded() {
        guard !AccessibilityController.isTrusted else {
            stopPolling()
            return
        }

        let alert = NSAlert()
        alert.messageText = "AltTab needs Accessibility access"
        alert.informativeText = "AltTab uses macOS Accessibility access to read windows and raise the exact window you select."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityController.openSystemSettings()
            startPolling()
        }
    }

    private func startPolling() {
        stopPolling()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if AccessibilityController.isTrusted {
                self.stopPolling()
            }
        }
    }

    private func stopPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    deinit {
        stopPolling()
    }
}
