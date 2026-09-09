import AppKit

final class CommandPaletteWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private struct Command {
        let title: String
        let detail: String
        let action: () -> Void
    }

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var commands: [Command] = []
    private var filteredCommands: [Command] = []
    private var localMonitor: Any?
    private var windowLoadGeneration = 0
    private let focusRestorer = WindowFocusRestorer()

    convenience init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 410), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "AltTab Command Palette"
        window.level = .floating
        window.center()
        self.init(window: window)
        window.delegate = self
        buildControls()
    }

    override func showWindow(_ sender: Any?) {
        show()
    }

    func show(showSwitcher: @escaping () -> Void = { }, showSettings: @escaping () -> Void = { }) {
        focusRestorer.capture()
        rebuildCommands(showSwitcher: showSwitcher, showSettings: showSettings)
        window?.center()
        super.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        searchField.stringValue = ""
        filterCommands()
        window?.recalculateKeyViewLoop()
        window?.makeFirstResponder(searchField)
        installKeyboardMonitor()
    }

    private func buildControls() {
        guard let window, let contentView = window.contentView else { return }
        contentView.autoresizingMask = [.width, .height]

        searchField.placeholderString = "Search commands and apps"
        searchField.font = NSFont.systemFont(ofSize: 16)
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.frame = NSRect(x: 18, y: contentView.bounds.height - 52, width: contentView.bounds.width - 36, height: 32)
        searchField.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(searchField)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Command"))
        column.width = contentView.bounds.width - 4
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 42
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(runSelected)

        let scrollView = NSScrollView(frame: NSRect(x: 18, y: 18, width: contentView.bounds.width - 36, height: contentView.bounds.height - 84))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        contentView.addSubview(scrollView)
    }

    private func rebuildCommands(showSwitcher: @escaping () -> Void, showSettings: @escaping () -> Void) {
        let result = [
            Command(title: "Show Switcher", detail: "Open the window switcher", action: showSwitcher),
            Command(title: "Open Settings", detail: "Change AltTab preferences", action: showSettings),
            Command(title: "Diagnostics & Permissions", detail: "View local status", action: { DiagnosticsWindowController.shared.showWindow(nil) })
        ]

        var commands = result
        for application in installedApplications() {
            commands.append(Command(title: "Launch \(application.name)", detail: application.url.path, action: {
                NSWorkspace.shared.open(application.url)
            }))
        }
        self.commands = commands
        filterCommands()

        windowLoadGeneration += 1
        let generation = windowLoadGeneration
        WindowCatalog.loadItems(for: .windows) { [weak self] loadedItems in
            guard let self, self.windowLoadGeneration == generation else { return }
            guard let frontWindow = loadedItems.first else { return }
            var updatedCommands = self.commands
            for action in WindowAction.allCases {
                let actionTitle: String
                if action == .moveToDisplay, let targetDisplay = WindowActionService.nextDisplayName(for: frontWindow) {
                    actionTitle = "Move window to \(targetDisplay)"
                } else {
                    actionTitle = action.title
                }
                updatedCommands.append(Command(title: "\(actionTitle): \(frontWindow.title)", detail: frontWindow.subtitle, action: {
                    WindowActionService.performWithConfirmation(action, on: frontWindow)
                }))
            }
            self.commands = updatedCommands
            self.filterCommands()
        }
    }

    private func installedApplications() -> [(name: String, url: URL)] {
        let applicationDirectories = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        var seen = Set<String>()
        var applications: [(String, URL)] = []

        for directory in applicationDirectories {
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.localizedNameKey], options: [.skipsHiddenFiles])) ?? []
            for url in urls where url.pathExtension == "app" {
                guard seen.insert(url.path).inserted else { continue }
                let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.deletingPathExtension().lastPathComponent
                applications.append((name, url))
            }
        }
        return applications.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    @objc private func searchChanged() {
        filterCommands()
    }

    private func filterCommands() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            filteredCommands = commands
            tableView.reloadData()
            selectFirstRow()
            return
        }
        filteredCommands = commands.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)
        }
        tableView.reloadData()
        selectFirstRow()
    }

    private func selectFirstRow() {
        guard !filteredCommands.isEmpty else { return }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true else { return event }
            switch event.keyCode {
            case 53:
                self.close()
                return nil
            case 126:
                self.moveSelection(by: -1)
                return nil
            case 125:
                self.moveSelection(by: 1)
                return nil
            case 48:
                self.moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1)
                return nil
            case 36, 76:
                self.runSelected()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
    }

    private func moveSelection(by offset: Int) {
        guard !filteredCommands.isEmpty else { return }
        let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let next = min(max(current + offset, 0), filteredCommands.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func runSelected() {
        let row = tableView.selectedRow
        guard filteredCommands.indices.contains(row) else { return }
        let action = filteredCommands[row].action
        close()
        action()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredCommands.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filteredCommands.indices.contains(row) else { return nil }
        let cell = NSTableCellView()
        let title = NSTextField(labelWithString: filteredCommands[row].title)
        title.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        title.frame = NSRect(x: 12, y: 20, width: tableView.bounds.width - 24, height: 18)
        title.autoresizingMask = [.width]
        cell.addSubview(title)

        let detail = NSTextField(labelWithString: filteredCommands[row].detail)
        detail.font = NSFont.systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 12, y: 3, width: tableView.bounds.width - 24, height: 15)
        detail.autoresizingMask = [.width]
        cell.addSubview(detail)
        return cell
    }

    deinit {
        removeKeyboardMonitor()
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyboardMonitor()
        focusRestorer.restore()
    }
}
