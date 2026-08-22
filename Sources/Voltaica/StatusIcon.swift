import AppKit
import SwiftUI
import VoltaicaCore

/// Draws the status item by hand.
///
/// `MenuBarExtra` will happily take a SwiftUI label, but the menu bar is 22 points tall and
/// unforgiving: drawing the glyph directly is the only way to control the optical weight, the
/// baseline of the percentage and the fill level down to the pixel.
enum StatusIcon {
    struct Style: Equatable {
        var charge: Double
        var mode: PolicyMode
        var showPercentage: Bool
        var coloured: Bool
        var limit: Int
        var limitActive: Bool
    }

    static func image(_ style: Style) -> NSImage {
        let bodyWidth: CGFloat = 25
        let bodyHeight: CGFloat = 12.5
        let nub: CGFloat = 2.2
        let textWidth: CGFloat = style.showPercentage ? 22 : 0
        let size = NSSize(width: bodyWidth + nub + textWidth + (style.showPercentage ? 3 : 0), height: 16)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            // A template image is recoloured by the menu bar itself, so black here means
            // "whatever colour the menu bar wants".
            let stroke = NSColor.black
            let tint = accentColour(style)
            let outline = style.coloured ? tint : stroke

            let bodyRect = CGRect(x: 0.9, y: (size.height - bodyHeight) / 2, width: bodyWidth - 1.8, height: bodyHeight)
            let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: 3.4, cornerHeight: 3.4, transform: nil)
            context.setLineWidth(1.25)
            context.setStrokeColor(outline.withAlphaComponent(0.9).cgColor)
            context.addPath(bodyPath)
            context.strokePath()

            // Terminal
            let nubRect = CGRect(x: bodyRect.maxX + 1.1, y: size.height / 2 - 3, width: nub, height: 6)
            context.setFillColor(outline.withAlphaComponent(0.75).cgColor)
            context.addPath(CGPath(roundedRect: nubRect, cornerWidth: 1, cornerHeight: 1, transform: nil))
            context.fillPath()

            // Fill
            let inset = bodyRect.insetBy(dx: 2.1, dy: 2.1)
            let fraction = max(0, min(1, style.charge / 100))
            if fraction > 0.01 {
                let fillRect = CGRect(x: inset.minX, y: inset.minY,
                                      width: max(1.6, inset.width * fraction), height: inset.height)
                context.setFillColor(fillColour(style).cgColor)
                context.addPath(CGPath(roundedRect: fillRect, cornerWidth: 1.4, cornerHeight: 1.4, transform: nil))
                context.fillPath()
            }

            // The limit, marked inside the body so the ceiling is visible at a glance.
            if style.limitActive, style.limit < 100 {
                let x = inset.minX + inset.width * CGFloat(style.limit) / 100
                context.setFillColor(outline.withAlphaComponent(0.85).cgColor)
                context.fill(CGRect(x: x - 0.6, y: bodyRect.minY - 0.4, width: 1.2, height: bodyHeight + 0.8))
            }

            if style.mode == .charging || style.mode == .topUp {
                drawBolt(in: context, rect: inset)
            }

            if style.showPercentage {
                let text = "\(Int(style.charge.rounded()))"
                let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: outline
                ]
                let attributed = NSAttributedString(string: text, attributes: attributes)
                let textSize = attributed.size()
                attributed.draw(at: NSPoint(x: size.width - textSize.width - 0.5,
                                            y: (size.height - textSize.height) / 2 + 0.5))
            }
            return true
        }

        // A template image inherits the menu bar's own colour, which is what you want unless the
        // user explicitly asked for the state colour.
        image.isTemplate = !style.coloured
        return image
    }

    /// Punches a bolt shaped hole through the fill, which reads more crisply at this size than
    /// drawing a second glyph on top of it.
    private static func drawBolt(in context: CGContext, rect: CGRect) {
        let cx = rect.midX
        let cy = rect.midY
        let points: [CGPoint] = [
            CGPoint(x: cx + 0.6, y: cy + 4.2),
            CGPoint(x: cx - 2.4, y: cy + 0.2),
            CGPoint(x: cx - 0.3, y: cy + 0.2),
            CGPoint(x: cx - 0.9, y: cy - 4.2),
            CGPoint(x: cx + 2.4, y: cy - 0.4),
            CGPoint(x: cx + 0.3, y: cy - 0.4)
        ]
        context.saveGState()
        context.setBlendMode(.destinationOut)
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() { context.addLine(to: point) }
        context.closePath()
        context.setLineWidth(1.6)
        context.setLineJoin(.round)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }

    private static func accentColour(_ style: Style) -> NSColor {
        NSColor(Palette.accent(for: style.mode)[1])
    }

    private static func fillColour(_ style: Style) -> NSColor {
        if style.coloured { return accentColour(style).withAlphaComponent(0.95) }
        if style.charge <= 10 { return NSColor.black.withAlphaComponent(0.95) }
        return NSColor.black.withAlphaComponent(0.62)
    }
}

/// The status item itself: recomputed whenever the model changes.
struct StatusItemLabel: View {
    var charge: Double
    var mode: PolicyMode
    var showPercentage: Bool
    var coloured: Bool
    var limit: Int
    var limitActive: Bool

    var body: some View {
        Image(nsImage: StatusIcon.image(.init(charge: charge,
                                              mode: mode,
                                              showPercentage: showPercentage,
                                              coloured: coloured,
                                              limit: limit,
                                              limitActive: limitActive)))
    }
}
