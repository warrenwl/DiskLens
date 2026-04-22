import AppKit
import CoreGraphics
import Foundation

// App icon dimensions: 1024x1024
let size = 1024.0
let scale: CGFloat = 2.0
let canvas = CGSize(width: size, height: size)

let image = NSImage(size: canvas)
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("No context") }

// Background - rounded rect with gradient
let bgRect = CGRect(origin: .zero, size: canvas)
let bgPath = CGPath(roundedRect: bgRect.insetBy(dx: 0, dy: 0), cornerWidth: 220, cornerHeight: 220, transform: nil)

// Dark blue-purple gradient background
let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.12, green: 0.14, blue: 0.28, alpha: 1.0),
        CGColor(red: 0.08, green: 0.10, blue: 0.22, alpha: 1.0),
    ] as CFArray, locations: [0.0, 1.0])!
ctx.addPath(bgPath)
ctx.clip()
ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

// Treemap blocks - represent the disk visualization
struct Block { let x, y, w, h: CGFloat; let color: CGColor }
let blocks: [Block] = [
    // Large block - green (safe clean)
    Block(x: 60, y: 60, w: 440, h: 360, color: CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 0.85)),
    // Medium block - orange (review)
    Block(x: 520, y: 60, w: 440, h: 200, color: CGColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 0.85)),
    // Small block - blue (system)
    Block(x: 520, y: 280, w: 200, h: 140, color: CGColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 0.85)),
    // Tiny block - gray (keep)
    Block(x: 740, y: 280, w: 220, h: 140, color: CGColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 0.85)),
    // Bottom row
    Block(x: 60, y: 440, w: 280, h: 240, color: CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 0.70)),
    Block(x: 360, y: 440, w: 280, h: 240, color: CGColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 0.70)),
    Block(x: 660, y: 440, w: 300, h: 120, color: CGColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 0.70)),
    Block(x: 660, y: 580, w: 300, h: 100, color: CGColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 0.70)),
]

for block in blocks {
    let r = CGRect(x: block.x, y: size - block.y - block.h, width: block.w, height: block.h)
    let path = CGPath(roundedRect: r.insetBy(dx: 3, dy: 3), cornerWidth: 18, cornerHeight: 18, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(block.color)
    ctx.fillPath()

    // Subtle border
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
    ctx.setLineWidth(2)
    ctx.strokePath()
}

// Magnifying glass (lens) overlay
let lensCenter = CGPoint(x: 620, y: size - 340)
let lensRadius: CGFloat = 180

// Glass circle
ctx.addEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
    width: lensRadius * 2, height: lensRadius * 2))
ctx.setFillColor(CGColor(red: 0.15, green: 0.18, blue: 0.35, alpha: 0.65))
ctx.fillPath()

// Glass border
ctx.addEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
    width: lensRadius * 2, height: lensRadius * 2))
ctx.setStrokeColor(CGColor(red: 0.9, green: 0.92, blue: 0.96, alpha: 0.9))
ctx.setLineWidth(12)
ctx.strokePath()

// Inner glow
ctx.addEllipse(in: CGRect(x: lensCenter.x - lensRadius + 12, y: lensCenter.y - lensRadius + 12,
    width: lensRadius * 2 - 24, height: lensRadius * 2 - 24))
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
ctx.setLineWidth(4)
ctx.strokePath()

// Lens handle
ctx.saveGState()
ctx.translateBy(x: lensCenter.x + lensRadius * 0.7, y: lensCenter.y - lensRadius * 0.7)
ctx.rotate(by: .pi / 4)
let handleRect = CGRect(x: 0, y: -10, width: 160, height: 20)
let handlePath = CGPath(roundedRect: handleRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
ctx.addPath(handlePath)
ctx.setFillColor(CGColor(red: 0.85, green: 0.87, blue: 0.90, alpha: 1.0))
ctx.fillPath()
ctx.addPath(handlePath)
ctx.setStrokeColor(CGColor(red: 0.6, green: 0.62, blue: 0.65, alpha: 1.0))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// Highlight reflection on lens
ctx.addEllipse(in: CGRect(x: lensCenter.x - 100, y: lensCenter.y - 80, width: 60, height: 40))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
ctx.fillPath()

image.unlockFocus()

// Export as PNG
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to create PNG")
}

let outputDir = FileManager.default.currentDirectoryPath
let outputPath = outputDir + "/AppIcon.png"
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Icon saved to: \(outputPath)")
print("Size: \(Int(size))x\(Int(size))")
