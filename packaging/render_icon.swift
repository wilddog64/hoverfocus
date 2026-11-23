import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: swift render_icon.swift <outdir>\n", stderr)
    exit(1)
}

let outdir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outdir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

let bgCol = color(237, 242, 239)
let strokeDark = color(22, 48, 43)
let whiteCol = color(255, 255, 255)
let trackCol = color(201, 214, 209)
let arcCol = color(14, 159, 138)

for (filename, px) in sizes {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
        fatalError("Failed to create bitmap context for \(px)x\(px)")
    }

    // Set origin to top-left on 100x100 grid
    let scale = CGFloat(px) / 100.0
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: scale, y: -scale)

    // 1. background: rounded rect 0,0,100,100, radius 22.5, #EDF2EF
    let bgRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 22.5, cornerHeight: 22.5, transform: nil)
    ctx.setFillColor(bgCol)
    ctx.addPath(bgPath)
    ctx.fillPath()

    // 2. back window: rounded rect x 14, y 18, w 52, h 44, radius 6, fill #FFFFFF, stroke #16302B width 2.4
    let backRect = CGRect(x: 14, y: 18, width: 52, height: 44)
    let backPath = CGPath(roundedRect: backRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
    ctx.setFillColor(whiteCol)
    ctx.addPath(backPath)
    ctx.fillPath()
    ctx.setStrokeColor(strokeDark)
    ctx.setLineWidth(2.4)
    ctx.addPath(backPath)
    ctx.strokePath()

    // 3. front window: rounded rect x 38, y 42, w 48, h 40, radius 6, fill #16302B
    let frontRect = CGRect(x: 38, y: 42, width: 48, height: 40)
    let frontPath = CGPath(roundedRect: frontRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
    ctx.setFillColor(strokeDark)
    ctx.addPath(frontPath)
    ctx.fillPath()

    // 4. dwell track: circle centre (29, 36), radius 10, stroke #C9D6D1 width 2.6
    ctx.setStrokeColor(trackCol)
    ctx.setLineWidth(2.6)
    ctx.addEllipse(in: CGRect(x: 29.0 - 10.0, y: 36.0 - 10.0, width: 20.0, height: 20.0))
    ctx.strokePath()

    // 5. dwell arc: same circle, 44 of its ~62.8 length from 12 o'clock clockwise, stroke #0E9F8A width 2.6, round caps
    // In flipped coords, 12 o'clock is -pi/2. Clockwise is increasing angle (+y).
    ctx.setStrokeColor(arcCol)
    ctx.setLineWidth(2.6)
    ctx.setLineCap(CGLineCap.round)
    let startAngle = -CGFloat.pi / 2.0
    let endAngle = startAngle + 4.4
    ctx.addArc(center: CGPoint(x: 29.0, y: 36.0), radius: 10.0, startAngle: startAngle, endAngle: endAngle, clockwise: false)
    ctx.strokePath()

    // 6. pointer arrow: polygon (29,36) (29,51) (32.6,47.8) (35.3,53.8) (37.8,52.7) (35.2,46.9) (39.9,46.7),
    // fill #16302B, stroke #FFFFFF width 1.2, round joins
    let arrowPath = CGMutablePath()
    arrowPath.move(to: CGPoint(x: 29.0, y: 36.0))
    arrowPath.addLine(to: CGPoint(x: 29.0, y: 51.0))
    arrowPath.addLine(to: CGPoint(x: 32.6, y: 47.8))
    arrowPath.addLine(to: CGPoint(x: 35.3, y: 53.8))
    arrowPath.addLine(to: CGPoint(x: 37.8, y: 52.7))
    arrowPath.addLine(to: CGPoint(x: 35.2, y: 46.9))
    arrowPath.addLine(to: CGPoint(x: 39.9, y: 46.7))
    arrowPath.closeSubpath()

    ctx.setFillColor(strokeDark)
    ctx.addPath(arrowPath)
    ctx.fillPath()

    ctx.setStrokeColor(whiteCol)
    ctx.setLineWidth(1.2)
    ctx.setLineJoin(CGLineJoin.round)
    ctx.addPath(arrowPath)
    ctx.strokePath()

    guard let image = ctx.makeImage() else {
        fatalError("Failed to make image from context")
    }

    let fileURL = URL(fileURLWithPath: (outdir as NSString).appendingPathComponent(filename))
    guard let dest = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Failed to create image destination for \(fileURL.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        fatalError("Failed to finalize image destination for \(fileURL.path)")
    }
}
