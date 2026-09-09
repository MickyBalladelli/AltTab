import Foundation

enum MRUStore {
    private static let key = "AltTab.mru.identifiers"
    private static let maximumEntries = 256

    static var savedIdentifiers: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func order(_ items: [SwitcherItem]) -> [SwitcherItem] {
        ordered(items, savedIdentifiers: savedIdentifiers)
    }

    static func ordered(_ items: [SwitcherItem], savedIdentifiers: [String]) -> [SwitcherItem] {
        var itemByIdentifier: [String: SwitcherItem] = [:]
        for item in items {
            itemByIdentifier[item.identifier] = item
            if let window = item.window {
                itemByIdentifier["window:\(window.windowID)"] = item
            }
        }
        var seenIdentifiers = Set<String>()
        let saved = savedIdentifiers.compactMap { identifier -> SwitcherItem? in
            guard let item = itemByIdentifier[identifier], seenIdentifiers.insert(item.identifier).inserted else { return nil }
            return item
        }
        let savedSet = Set(saved.map(\.identifier))
        let newItems = items.filter { !savedSet.contains($0.identifier) }
        return saved + newItems
    }

    static func record(_ item: SwitcherItem) {
        var identifiers = savedIdentifiers
        let identifiersToReplace = Set([item.identifier] + (item.window.map { ["window:\($0.windowID)"] } ?? []))
        identifiers.removeAll { identifiersToReplace.contains($0) }
        identifiers.insert(item.identifier, at: 0)
        UserDefaults.standard.set(Array(identifiers.prefix(maximumEntries)), forKey: key)
    }
}
