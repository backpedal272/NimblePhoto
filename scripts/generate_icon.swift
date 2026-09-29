// Generates the NimblePhoto app icon master (Nimble Icons style guide v2).
// Concept: "a photo tag" — a Finder-style tag whose eyelet doubles as the
// sun over two hills. Classifying photos = tagging them.
//
// Usage: swift scripts/generate_icon.swift <output.png>
// Prints a pixel check of the background corners and the mark.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let nimbleBlue = CGColor(srgbRed: 0 / 255, green: 154 / 255, blue: 214 / 255, alpha: 1)  // #009AD6
let deepBlue = CGColor(srgbRed: 0 / 255, green: 108 / 255, blue: 165 / 255, alpha: 1)    // #006CA5
let cream = CGColor(srgbRed: 250 / 255, green: 248 / 255, blue: 244 / 255, alpha: 1)     // #FAF8F4

/// Closed polygon with each corner rounded by its own radius.
func roundedPolygon(_ points: [CGPoint], radii: [CGFloat]) -> CGPath {
    let path = CGMutablePath()
    let n = points.count
    path.move(to: CGPoint(x: (points[n - 1].x + points[0].x) / 2, y: (points[n - 1].y + points[0].y) / 2))
    for i in 0..<n {
        path.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % n], radius: radii[i])
    }
    path.closeSubpath()
    return path
}

func circle(center: CGPoint, diameter d: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d), transform: nil)
}

let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                    space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// Background: diagonal gradient, Nimble Blue top-left → Deep Blue bottom-right.
let gradient = CGGradient(colorsSpace: srgb, colors: [nimbleBlue, deepBlue] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// 512 grid, top-left origin.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 2, y: -2)

// Tag body: 328 × 212 (64% of the width), pointed end on the left.
let tag = roundedPolygon([
    CGPoint(x: 92, y: 256),   // tip
    CGPoint(x: 176, y: 150),  // top shoulder
    CGPoint(x: 420, y: 150),
    CGPoint(x: 420, y: 362),
    CGPoint(x: 176, y: 362),  // bottom shoulder
], radii: [34, 30, 60, 60, 30])
ctx.addPath(tag)
ctx.setFillColor(cream)
ctx.fillPath()

ctx.setFillColor(nimbleBlue)

// Eyelet / sun: 46, matching the family's cut-in detail size.
ctx.addPath(circle(center: CGPoint(x: 164, y: 256), diameter: 46))
ctx.fillPath()

// Hills: two peaks on a flat base, all corners softened.
let hillsX: CGFloat = 214, hillsBase: CGFloat = 318, hillsW: CGFloat = 172, hillsH: CGFloat = 110
ctx.addPath(roundedPolygon([
    CGPoint(x: hillsX, y: hillsBase),
    CGPoint(x: hillsX + hillsW * 0.30, y: hillsBase - hillsH * 0.62),
    CGPoint(x: hillsX + hillsW * 0.46, y: hillsBase - hillsH * 0.36),
    CGPoint(x: hillsX + hillsW * 0.70, y: hillsBase - hillsH),
    CGPoint(x: hillsX + hillsW, y: hillsBase),
], radii: [10, 14, 10, 14, 10]))
ctx.fillPath()

// Write the master (sRGB, no alpha).
let image = ctx.makeImage()!
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Could not write \(outPath)") }

// Pixel check (style guide §6). Coordinates are in image pixels, top-left origin.
let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
func hex(_ x: Int, _ y: Int) -> String {
    let i = (y * size + x) * 4
    return String(format: "#%02X%02X%02X", pixels[i], pixels[i + 1], pixels[i + 2])
}
let checks = [("top-left", hex(0, 0), "#009AD6"),
              ("bottom-right", hex(size - 1, size - 1), "#006CA5"),
              ("mark", hex(2 * 300, 2 * 190), "#FAF8F4")]
var ok = true
for (name, got, want) in checks {
    print("\(name): \(got) (expected \(want))\(got == want ? "" : "  ✗")")
    ok = ok && got == want
}
print(ok ? "Pixel check passed → \(outPath)" : "Pixel check FAILED")
exit(ok ? 0 : 1)
