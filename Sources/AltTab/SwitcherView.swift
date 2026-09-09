import AppKit

final class SwitcherView: NSView {
    var items: [WindowItem] = [] { didSet { needsDisplay = true } }
    var selectedIndex = 0 { didSet { needsDisplay = true } }
    var onItemSelected: ((Int) -> Void)?
    var onItemCommitted: (() -> Void)?

    private let maximumVisibleItems = 5
    private let cardWidth: CGFloat = 108
    private let cardHeight: CGFloat = 125
    private let cardGap: CGFloat = 10

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.08, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()
        let visibleRange = visibleRange()
        let totalWidth = CGFloat(visibleRange.count) * cardWidth + CGFloat(max(0, visibleRange.count - 1)) * cardGap
        var x = (bounds.width - totalWidth) / 2
        for index in visibleRange {
            let item = items[index]
            let rect = NSRect(x: x, y: 23, width: cardWidth, height: cardHeight)
            if index == selectedIndex {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 12, yRadius: 12).fill()
            }
            NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            item.icon.draw(in: NSRect(x: x + 30, y: 78, width: 48, height: 48), from: .zero, operation: .sourceOver, fraction: 1)
            let appLabel = (item.app.localizedName ?? "App") as NSString
            let appAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
            appLabel.draw(in: NSRect(x: x + 7, y: 51, width: cardWidth - 14, height: 16), withAttributes: appAttributes)

            let titleLabel = item.title as NSString
            let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
            titleLabel.draw(in: NSRect(x: x + 7, y: 35, width: cardWidth - 14, height: 15), withAttributes: titleAttributes)
            x += cardWidth + cardGap
        }
        let hint = "Option-Tab cycle    Shift reverse    Arrows / 1-9 select    Return switch    Esc cancel"
        (hint as NSString).draw(at: NSPoint(x: 18, y: 7), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor])
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = itemIndex(at: point) else { return }
        onItemSelected?(index)
        onItemCommitted?()
    }

    private func visibleRange() -> Range<Int> {
        guard !items.isEmpty else { return 0..<0 }
        let count = min(items.count, maximumVisibleItems)
        guard items.count > maximumVisibleItems else { return 0..<count }

        let half = maximumVisibleItems / 2
        let start = min(max(0, selectedIndex - half), items.count - maximumVisibleItems)
        return start..<(start + maximumVisibleItems)
    }

    private func itemIndex(at point: NSPoint) -> Int? {
        let range = visibleRange()
        guard !range.isEmpty else { return nil }
        let totalWidth = CGFloat(range.count) * cardWidth + CGFloat(max(0, range.count - 1)) * cardGap
        let startX = (bounds.width - totalWidth) / 2
        guard point.y >= 23, point.y <= 23 + cardHeight else { return nil }

        let position = Int((point.x - startX) / (cardWidth + cardGap))
        guard range.contains(range.lowerBound + position) else { return nil }
        let cardStart = startX + CGFloat(position) * (cardWidth + cardGap)
        guard point.x >= cardStart, point.x <= cardStart + cardWidth else { return nil }
        return range.lowerBound + position
    }
}
