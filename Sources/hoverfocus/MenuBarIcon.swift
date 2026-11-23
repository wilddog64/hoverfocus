import AppKit
import HoverFocusCore

public enum MenuBarIcon {
    public static func makeImage(style: MenuBarIconStyle, darkBar: Bool, dimmed: Bool) -> NSImage {
        let colors = MenuModel.iconColors(style: style, darkBar: darkBar, dimmed: dimmed)
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            func makeColor(_ rgba: RGBA) -> CGColor {
                CGColor(
                    red: CGFloat(rgba.r) / 255.0,
                    green: CGFloat(rgba.g) / 255.0,
                    blue: CGFloat(rgba.b) / 255.0,
                    alpha: CGFloat(rgba.a)
                )
            }

            // Window: rounded rect x 7.5, y 7.5, w 9, h 8, radius 1.5, filled with glyph colour
            let windowRect = CGRect(x: 7.5, y: 7.5, width: 9.0, height: 8.0)
            let windowPath = CGPath(roundedRect: windowRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            ctx.setFillColor(makeColor(colors.glyph))
            ctx.addPath(windowPath)
            ctx.fillPath()

            // Dwell track: circle centre (6, 6), radius 4.2, stroke 1.5, track colour
            ctx.setStrokeColor(makeColor(colors.track))
            ctx.setLineWidth(1.5)
            ctx.addEllipse(in: CGRect(x: 6.0 - 4.2, y: 6.0 - 4.2, width: 8.4, height: 8.4))
            ctx.strokePath()

            // Dwell arc: same circle, 40% length, starting at 12 o'clock, clockwise, round caps, arc colour
            ctx.setStrokeColor(makeColor(colors.arc))
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            let startAngle: CGFloat = -CGFloat.pi / 2.0
            let endAngle: CGFloat = startAngle + (CGFloat.pi * 2.0 * 0.40)
            ctx.addArc(center: CGPoint(x: 6.0, y: 6.0), radius: 4.2, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            ctx.strokePath()

            // Pointer: filled circle centre (6, 6), radius 1.4, glyph colour
            ctx.setFillColor(makeColor(colors.glyph))
            ctx.fillEllipse(in: CGRect(x: 6.0 - 1.4, y: 6.0 - 1.4, width: 2.8, height: 2.8))

            return true
        }
        img.isTemplate = colors.template
        return img
    }
}
