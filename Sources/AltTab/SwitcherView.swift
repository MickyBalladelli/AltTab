import AppKit

final class SwitcherView: NSView {
    var items: [WindowItem] = [] { didSet { needsDisplay = true } }
    var selectedIndex = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.08, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()
        let cardWidth: CGFloat = 108
        let gap: CGFloat = 10
        let visibleItems = Array(items.prefix(5))
        let totalWidth = CGFloat(visibleItems.count) * cardWidth + CGFloat(max(0, visibleItems.count - 1)) * gap
        var x = (bounds.width - totalWidth) / 2
        for (index, item) in visibleItems.enumerated() {
            let rect = NSRect(x: x, y: 23, width: cardWidth, height: 125)
            if index == selectedIndex {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 12, yRadius: 12).fill()
            }
            NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            item.icon.size = NSSize(width: 48, height: 48)
            item.icon.draw(in: NSRect(x: x + 30, y: 78, width: 48, height: 48), from: .zero, operation: .sourceOver, fraction: 1)
            let label = (item.app.localizedName ?? item.title) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
            label.draw(in: NSRect(x: x + 7, y: 38, width: cardWidth - 14, height: 30), withAttributes: attributes)
            x += cardWidth + gap
        }
        let hint = "Option-Tab  cycle    Return  switch    Esc  cancel"
        (hint as NSString).draw(at: NSPoint(x: 18, y: 7), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor])
    }
}
