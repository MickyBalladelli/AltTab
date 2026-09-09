import Foundation

struct SwitcherState {
    private(set) var sourceItems: [SwitcherItem] = []
    private(set) var items: [SwitcherItem] = []
    private(set) var selectedIndex = 0
    private(set) var searchQuery = ""
    private(set) var isVisible = false

    var hasSearchQuery: Bool { !searchQuery.isEmpty }
    var resultCount: Int { items.count }
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
    mutating func setSearchQuery(_ query: String) -> Bool {
        guard isVisible else { return false }
        searchQuery = query
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
            let queryParts = searchQuery
                .split { $0.isWhitespace }
                .map { String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            let scoredItems = sourceItems.enumerated().compactMap { index, item -> (index: Int, item: SwitcherItem, score: Int)? in
                let fields = [item.title, item.subtitle, item.app?.localizedName ?? ""]
                    .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
                var totalScore = 0
                for queryPart in queryParts {
                    guard let bestScore = fields.compactMap({ fuzzyScore(queryPart, in: $0) }).max() else { return nil }
                    totalScore += bestScore
                }
                return (index, item, totalScore)
            }
            items = scoredItems
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score { return lhs.index < rhs.index }
                    return lhs.score > rhs.score
                }
                .map(\.item)
        }
        selectedIndex = previousIdentifier.flatMap { identifier in
            items.firstIndex { $0.identifier == identifier }
        } ?? 0
    }

    private func fuzzyScore(_ query: String, in text: String) -> Int? {
        guard !query.isEmpty, !text.isEmpty else { return nil }
        if let exactRange = text.range(of: query) {
            let prefixBonus = exactRange.lowerBound == text.startIndex ? 160 : 80
            return 600 + prefixBonus - text.distance(from: text.startIndex, to: exactRange.lowerBound)
        }

        let queryCharacters = Array(query)
        let textCharacters = Array(text)
        var textIndex = 0
        var previousMatch = -1
        var gaps = 0
        var consecutiveMatches = 0

        for queryCharacter in queryCharacters {
            guard let matchIndex = textCharacters[textIndex...].firstIndex(of: queryCharacter) else { return nil }
            if previousMatch + 1 == matchIndex {
                consecutiveMatches += 1
            } else if previousMatch >= 0 {
                gaps += matchIndex - previousMatch - 1
            }
            previousMatch = matchIndex
            textIndex = matchIndex + 1
        }

        return 260 + consecutiveMatches * 24 - gaps * 3 - max(0, textCharacters.count - queryCharacters.count)
    }
}
