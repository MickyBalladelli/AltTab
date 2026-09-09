import Foundation

struct SwitcherState {
    private(set) var sourceItems: [SwitcherItem] = []
    private(set) var items: [SwitcherItem] = []
    private(set) var selectedIndex = 0
    private(set) var searchQuery = ""
    private(set) var isVisible = false

    var hasSearchQuery: Bool { !searchQuery.isEmpty }
    var selectedItem: SwitcherItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    @discardableResult
    mutating func begin(items: [SwitcherItem]) -> Bool {
        sourceItems = items
        guard !items.isEmpty else {
            self.items = []
            selectedIndex = 0
            isVisible = false
            return false
        }
        self.items = items
        selectedIndex = 0
        searchQuery = ""
        isVisible = true
        return true
    }

    @discardableResult
    mutating func advance() -> Bool {
        guard isVisible, !items.isEmpty else { return false }
        selectedIndex = (selectedIndex + 1) % items.count
        return true
    }

    @discardableResult
    mutating func previous() -> Bool {
        guard isVisible, !items.isEmpty else { return false }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
        return true
    }

    @discardableResult
    mutating func select(index: Int) -> Bool {
        guard isVisible, items.indices.contains(index) else { return false }
        selectedIndex = index
        return true
    }

    @discardableResult
    mutating func appendSearchText(_ text: String) -> Bool {
        guard isVisible else { return false }
        let additions = text.filter { !$0.isNewline && $0 != "\u{7f}" }
        guard !additions.isEmpty else { return false }
        searchQuery.append(contentsOf: additions)
        applySearch()
        return true
    }

    @discardableResult
    mutating func deleteSearchCharacter() -> Bool {
        guard isVisible, !searchQuery.isEmpty else { return false }
        searchQuery.removeLast()
        applySearch()
        return true
    }

    @discardableResult
    mutating func clearSearch() -> Bool {
        guard isVisible, !searchQuery.isEmpty else { return false }
        searchQuery = ""
        applySearch()
        return true
    }

    mutating func cancel() {
        isVisible = false
        searchQuery = ""
    }

    @discardableResult
    mutating func removeSelected() -> Bool {
        guard let selectedItem else { return false }
        items.removeAll { $0.identifier == selectedItem.identifier }
        sourceItems.removeAll { $0.identifier == selectedItem.identifier }
        selectedIndex = min(selectedIndex, max(0, items.count - 1))
        if items.isEmpty {
            cancel()
        }
        return true
    }

    mutating func commit() -> SwitcherItem? {
        guard isVisible, items.indices.contains(selectedIndex) else {
            cancel()
            return nil
        }
        let item = items[selectedIndex]
        cancel()
        return item
    }

    private mutating func applySearch() {
        let previousIdentifier = items.indices.contains(selectedIndex) ? items[selectedIndex].identifier : nil
        if searchQuery.isEmpty {
            items = sourceItems
        } else {
            items = sourceItems.filter { item in
                item.title.localizedCaseInsensitiveContains(searchQuery) ||
                item.subtitle.localizedCaseInsensitiveContains(searchQuery) ||
                (item.app?.localizedName?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            }
        }
        selectedIndex = previousIdentifier.flatMap { identifier in
            items.firstIndex { $0.identifier == identifier }
        } ?? 0
    }
}
