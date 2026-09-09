import Foundation

enum SearchHistoryStore {
    private static let key = "AltTab.search.recentTerms"
    private static let maximumEntries = 8

    static var terms: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ query: String) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        let existing = terms.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        UserDefaults.standard.set(Array(([term] + existing).prefix(maximumEntries)), forKey: key)
    }
}
