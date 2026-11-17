import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the AirSurf app icon, a compass with a surfboard for a needle, as the three tvOS
// parallax layers (back, middle, front) in a 400x240 design space with a y-down origin,
// and writes them into the app's asset catalog. Light comes from the top.
//
//     swift Tools/render_app_icon.swift
//
// Run from the repository root, then rebuild.

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}
func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }

typealias Layer = (CGContext) -> Void
struct Concept { let name: String; let title: String; let back: Layer; let middle: Layer; let front: Layer }

// MARK: - Compass

let surfCompass: Concept = {
    let c = CGPoint(x: 200, y: 120), r: CGFloat = 88
    let back: Layer = { ctx in
        ctx.drawLinearGradient(gradient([rgb(0x123B70), rgb(0x071C3D)]), start: .zero, end: CGPoint(x: 0, y: 240), options: [])
        ctx.drawRadialGradient(gradient([rgb(0x2BB5E8, 0.35), rgb(0x2BB5E8, 0)]), startCenter: c, startRadius: 0, endCenter: c, endRadius: 200, options: [])
    }
    let middle: Layer = { ctx in
        // White bezel, then a sky-to-ocean dial face with tick marks.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 9), blur: 20, color: rgb(0x020B1C, 0.6))
        ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillEllipse(in: circle(c, r))
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addEllipse(in: circle(c, r)); ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(0xFFFFFF), rgb(0xD5E3EE)]), start: CGPoint(x: 0, y: c.y - r), end: CGPoint(x: 0, y: c.y + r), options: [])
        ctx.restoreGState()
        let face = r - 9
        ctx.saveGState()
        ctx.addEllipse(in: circle(c, face)); ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(0x2EE6D6), rgb(0x0FA3C4), rgb(0x0A4E8C)], [0, 0.5, 1]),
                               start: CGPoint(x: 0, y: c.y - face), end: CGPoint(x: 0, y: c.y + face), options: [])
        // Two gentle swells across the lower half of the dial.
        for (i, y) in [CGFloat(146), 172].enumerated() {
            let swell = CGMutablePath()
            swell.move(to: CGPoint(x: c.x - face, y: y))
            swell.addCurve(to: CGPoint(x: c.x + face, y: y), control1: CGPoint(x: c.x - 30, y: y - 16), control2: CGPoint(x: c.x + 30, y: y + 16))
            swell.addLine(to: CGPoint(x: c.x + face, y: 240)); swell.addLine(to: CGPoint(x: c.x - face, y: 240)); swell.closeSubpath()
            ctx.addPath(swell); ctx.setFillColor(rgb(0x063B73, i == 0 ? 0.28 : 0.3)); ctx.fillPath()
        }
        ctx.restoreGState()
        // Marks only at north, east, south and west, plus small dots between.
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.95)); ctx.setLineCap(.round); ctx.setLineWidth(4)
        ctx.setFillColor(rgb(0xFFFFFF, 0.7))
        for i in 0..<16 {
            let a = CGFloat(i) / 16 * 2 * .pi
            if i % 4 == 0 {
                ctx.move(to: CGPoint(x: c.x + cos(a) * (face - 7), y: c.y + sin(a) * (face - 7)))
                ctx.addLine(to: CGPoint(x: c.x + cos(a) * (face - 19), y: c.y + sin(a) * (face - 19)))
                ctx.strokePath()
            } else {
                ctx.fillEllipse(in: circle(CGPoint(x: c.x + cos(a) * (face - 10), y: c.y + sin(a) * (face - 10)), 2.2))
            }
        }
    }
    let front: Layer = { ctx in
        // The needle is a surfboard pointing north-east: coral nose, white tail, a stringer down the middle.
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: .pi / 4)
        let board = CGMutablePath()
        board.move(to: CGPoint(x: 0, y: -70))
        board.addCurve(to: CGPoint(x: 10, y: 54), control1: CGPoint(x: 15, y: -34), control2: CGPoint(x: 16, y: 22))
        board.addCurve(to: CGPoint(x: -10, y: 54), control1: CGPoint(x: 6, y: 68), control2: CGPoint(x: -6, y: 68))
        board.addCurve(to: CGPoint(x: 0, y: -70), control1: CGPoint(x: -16, y: 22), control2: CGPoint(x: -15, y: -34))
        board.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 5, height: 5), blur: 10, color: rgb(0x031533, 0.55))
        ctx.addPath(board); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(board); ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(0xFFC24B), rgb(0xFF6A3D), rgb(0xF2455B)], [0, 0.55, 1]),
                               start: CGPoint(x: 0, y: -70), end: CGPoint(x: 0, y: 66), options: [])
        ctx.setFillColor(rgb(0xFFFFFF)); ctx.fill(CGRect(x: -20, y: 18, width: 40, height: 8))
        ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.35), rgb(0xFFFFFF, 0)]), start: CGPoint(x: -14, y: 0), end: CGPoint(x: 4, y: 0), options: [])
        ctx.restoreGState()
        ctx.setStrokeColor(rgb(0x0A2C55, 0.28)); ctx.setLineWidth(1.6)
        ctx.move(to: CGPoint(x: 0, y: -62)); ctx.addLine(to: CGPoint(x: 0, y: 60)); ctx.strokePath()
        ctx.restoreGState()
        ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillEllipse(in: circle(c, 5.5))
        ctx.setStrokeColor(rgb(0x0A2C55, 0.3)); ctx.setLineWidth(1.2); ctx.strokeEllipse(in: circle(c, 5.5))
    }
    return Concept(name: "surf-compass", title: "2  Surf compass", back: back, middle: middle, front: front)
}()

// MARK: - Rendering

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func layerImage(_ draw: Layer, _ w: Int, _ h: Int) -> CGImage {
    let ctx = makeContext(w, h)
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: CGFloat(w) / 400, y: -CGFloat(h) / 240)
    draw(ctx)
    return ctx.makeImage()!
}
func save(_ image: CGImage, _ url: URL) {
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, image, nil); CGImageDestinationFinalize(d)
}

let catalog = URL(fileURLWithPath: "AirSurf/Assets.xcassets/App Icon & Top Shelf Image.brandassets")
let icon = surfCompass
for (stack, files) in [("App Icon - Small", [("", 400, 240), ("@2x", 800, 480)]), ("App Icon - Large", [("", 1280, 768)])] {
    for (layerName, draw) in [("Back", icon.back), ("Middle", icon.middle), ("Front", icon.front)] {
        let folder = catalog.appendingPathComponent("\(stack).imagestack/\(layerName).imagestacklayer/Content.imageset")
        for (suffix, w, h) in files {
            save(layerImage(draw, w, h), folder.appendingPathComponent("\(layerName.lowercased())\(suffix).png"))
        }
    }
}
print("Icon layers written to \(catalog.path)")
