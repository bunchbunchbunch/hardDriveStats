// Draws the app icon: a disk usage pie with one amber slice pulled out, the space you can reclaim.
// Writes every Mac icon size into the asset catalog.
// Usage: swift make-icon.swift Sources/App/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func context(_ side: Int, alpha: Bool) -> CGContext {
    CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue
    )!
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

let ctx = context(size, alpha: true)
// Work top-down, like the design coordinates.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

// Background, edge to edge (macOS applies the rounded mask).
let background = CGGradient(colorsSpace: space, colors: [rgb(0x26365C), rgb(0x0C1226)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: .zero, end: CGPoint(x: 0, y: size), options: [])

// Pie geometry. Angles are degrees clockwise from 12 o'clock.
let center = CGPoint(x: 530, y: 520)
let radius: CGFloat = 318
func point(_ degrees: CGFloat, _ r: CGFloat, from c: CGPoint = center) -> CGPoint {
    let a = degrees * .pi / 180
    return CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
}

func slice(from start: CGFloat, to end: CGFloat, center c: CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.move(to: c)
    for step in 0...180 {
        path.addLine(to: point(start + (end - start) * CGFloat(step) / 180, radius, from: c))
    }
    path.closeSubpath()
    return path
}

func fill(_ path: CGPath, top: CGColor, bottom: CGColor) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let box = path.boundingBox
    let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: box.minY), end: CGPoint(x: 0, y: box.maxY), options: [])
    ctx.restoreGState()
}

// Clockwise from 12 o'clock: used space, then the reclaimable slice, then free space.
let reclaim: (start: CGFloat, end: CGFloat) = (196, 258)

// Used and free share the pie; cut a gap where they meet at 12 o'clock so they read apart.
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
fill(slice(from: 0, to: reclaim.start, center: center), top: rgb(0x5AA2FF), bottom: rgb(0x2D6BEA))
fill(slice(from: reclaim.end, to: 360, center: center), top: rgb(0xE6ECF7), bottom: rgb(0xB8C4DA))
ctx.setBlendMode(.clear)
ctx.setLineWidth(26)
ctx.move(to: center)
ctx.addLine(to: point(0, radius + 20))
ctx.strokePath()
ctx.setBlendMode(.normal)
ctx.endTransparencyLayer()

// The reclaimable slice, pulled outward along its middle.
let middle = (reclaim.start + reclaim.end) / 2
let pulled = point(middle, 64)
fill(slice(from: reclaim.start, to: reclaim.end, center: pulled), top: rgb(0xFFC94D), bottom: rgb(0xF59E0B))

// The App Store wants an opaque icon: flatten onto the background before saving.
let art = ctx.makeImage()!
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for side in [16, 32, 64, 128, 256, 512, 1024] {
    let out = context(side, alpha: false)
    out.interpolationQuality = .high
    out.draw(art, in: CGRect(x: 0, y: 0, width: side, height: side))
    let url = folder.appending(path: "icon_\(side).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("couldn't write \(url.path)") }
}
