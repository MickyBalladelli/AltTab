import AppKit

final class SwitcherView: NSView {
    var items: [SwitcherItem] = [] { didSet { needsDisplay = true } }
    var selectedIndex = 0 { didSet { needsDisplay = true } }
    var onItemSelected: ((Int) -> Void)?
    var onItemCommitted: (() -> Void)?

    private static let minimumCardWidth: CGFloat = 112
    private static let cardGap: CGFloat = 10

    static func preferredSize(for itemCount: Int) -> NSSize {
        let columns = max(1, min(SettingsStore.columns, 10))
        let visibleCount = max(1, min(itemCount, columns))
        let thumbnailSize = CGFloat(SettingsStore.thumbnailSize)
        let cardWidth = max(minimumCardWidth, thumbnailSize + 42)
        let cardHeight = SettingsStore.showLabels ? max(130, thumbnailSize + 82) : max(108, thumbnailSize + 38)
        let width = CGFloat(visibleCount) * cardWidth + CGFloat(max(0, visibleCount - 1)) * cardGap + 36
        return NSSize(width: max(width, 320), height: cardHeight + 48)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = CGFloat(SettingsStore.cornerRadius)
        let opacity = CGFloat(SettingsStore.opacity)
        NSColor(calibratedWhite: 0.08, alpha: opacity).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let range = visibleRange()
        let cardWidth = Self.cardWidth
        let cardHeight = Self.cardHeight
        let totalWidth = CGFloat(range.count) * cardWidth + CGFloat(max(0, range.count - 1)) * Self.cardGap
        var x = (bounds.width - totalWidth) / 2

        for index in range {
            let item = items[index]
            let rect = NSRect(x: x, y: 29, width: cardWidth, height: cardHeight)
            let cardRadius = max(6, radius - 4)
            if index == selectedIndex {
                (NSColor(hex: SettingsStore.accentColorHex) ?? .controlAccentColor).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: cardRadius + 3, yRadius: cardRadius + 3).fill()
            }

            NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: cardRadius, yRadius: cardRadius).fill()
            drawImage(for: item, in: rect)

            if SettingsStore.showLabels {
                let appLabel = item.title as NSString
                let appAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: centeredParagraphStyle()
                ]
                appLabel.draw(in: NSRect(x: rect.minX + 7, y: rect.minY + 30, width: rect.width - 14, height: 17), withAttributes: appAttributes)

                let subtitleLabel = item.subtitle as NSString
                let subtitleAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: centeredParagraphStyle()
                ]
                subtitleLabel.draw(in: NSRect(x: rect.minX + 7, y: rect.minY + 13, width: rect.width - 14, height: 15), withAttributes: subtitleAttributes)
            }
            x += cardWidth + Self.cardGap
        }

        let hint = "Option-Tab cycle    Shift reverse    Arrows / 1-9 select    Return switch    Esc cancel"
        (hint as NSString).draw(at: NSPoint(x: 18, y: 9), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor])
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = itemIndex(at: point) else { return }
        onItemSelected?(index)
        onItemCommitted?()
    }

    private static var cardWidth: CGFloat {
        max(minimumCardWidth, CGFloat(SettingsStore.thumbnailSize) + 42)
    }

    private static var cardHeight: CGFloat {
        SettingsStore.showLabels ? max(130, CGFloat(SettingsStore.thumbnailSize) + 82) : max(108, CGFloat(SettingsStore.thumbnailSize) + 38)
    }

    private func drawImage(for item: SwitcherItem, in rect: NSRect) {
        let iconSize = CGFloat(SettingsStore.iconSize)
        if let thumbnail = item.thumbnail {
            let thumbnailSize = CGFloat(SettingsStore.thumbnailSize)
            let thumbnailRect = NSRect(
                x: rect.midX - thumbnailSize / 2,
                y: rect.maxY - thumbnailSize - 13,
                width: thumbnailSize,
                height: thumbnailSize
            )
            thumbnail.draw(in: thumbnailRect, from: .zero, operation: .sourceOver, fraction: 1)

            let badgeSize = min(iconSize, 28)
            item.icon.draw(in: NSRect(x: thumbnailRect.maxX - badgeSize + 4, y: thumbnailRect.minY - 4, width: badgeSize, height: badgeSize), from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            let iconRect = NSRect(
                x: rect.midX - iconSize / 2,
                y: rect.maxY - iconSize - 16,
                width: iconSize,
                height: iconSize
            )
            item.icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    private func visibleRange() -> Range<Int> {
        guard !items.isEmpty else { return 0..<0 }
        let maximumVisibleItems = max(1, min(SettingsStore.columns, 10))
        let count = min(items.count, maximumVisibleItems)
        guard items.count > maximumVisibleItems else { return 0..<count }

        let half = maximumVisibleItems / 2
        let start = min(max(0, selectedIndex - half), items.count - maximumVisibleItems)
        return start..<(start + maximumVisibleItems)
    }

    private func itemIndex(at point: NSPoint) -> Int? {
        let range = visibleRange()
        guard !range.isEmpty else { return nil }
        let totalWidth = CGFloat(range.count) * Self.cardWidth + CGFloat(max(0, range.count - 1)) * Self.cardGap
        let startX = (bounds.width - totalWidth) / 2
        let cardHeight = Self.cardHeight
        guard point.y >= 29, point.y <= 29 + cardHeight else { return nil }

        let position = Int((point.x - startX) / (Self.cardWidth + Self.cardGap))
        guard range.contains(range.lowerBound + position) else { return nil }
        let cardStart = startX + CGFloat(position) * (Self.cardWidth + Self.cardGap)
        guard point.x >= cardStart, point.x <= cardStart + Self.cardWidth else { return nil }
        return range.lowerBound + position
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }
}
