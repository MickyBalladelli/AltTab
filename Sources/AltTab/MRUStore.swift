import Foundation

enum MRUStore {
    private static let key = "AltTab.mru.identifiers"
    private static let maximumEntries = 256

    static var savedIdentifiers: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func order(_ items: [SwitcherItem]) -> [SwitcherItem] {
        let itemByIdentifier = Dictionary(uniqueKeysWithValues: items.map { ($0.identifier, $0) })
        let saved = savedIdentifiers.compactMap { itemByIdentifier[$0] }
        let savedSet = Set(saved.map(\.identifier))
        let newItems = items.filter { !savedSet.contains($0.identifier) }
        return saved + newItems
    }

    static func record(_ item: SwitcherItem) {
        var identifiers = savedIdentifiers
        identifiers.removeAll { $0 == item.identifier }
        identifiers.insert(item.identifier, at: 0)
        UserDefaults.standard.set(Array(identifiers.prefix(maximumEntries)), forKey: key)
    }
}
