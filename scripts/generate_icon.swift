import AppKit
import CoreGraphics
import Foundation

let size = 1024.0
let canvas = CGSize(width: size, height: size)

let image = NSImage(size: canvas)
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("No context") }

// Background - medium dark blue-gray
let bgRect = CGRect(origin: .zero, size: canvas)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 220, cornerHeight: 220, transform: nil)

let bgGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.22, green: 0.25, blue: 0.34, alpha: 1.0),
        CGColor(red: 0.14, green: 0.16, blue: 0.24, alpha: 1.0),
    ] as CFArray, locations: [0.0, 1.0])!
ctx.addPath(bgPath)
ctx.clip()
ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

// Green ambient glow behind the wave
ctx.addEllipse(in: CGRect(x: 120, y: 280, width: 784, height: 464))
ctx.setFillColor(CGColor(red: 0.10, green: 0.80, blue: 0.35, alpha: 0.18))
ctx.fillPath()

// Outer ring
ctx.addEllipse(in: CGRect(x: 220, y: 220, width: 584, height: 584))
ctx.setStrokeColor(CGColor(red: 0.10, green: 0.80, blue: 0.35, alpha: 0.25))
ctx.setLineWidth(5)
ctx.strokePath()

// Inner ring
ctx.addEllipse(in: CGRect(x: 300, y: 300, width: 424, height: 424))
ctx.setStrokeColor(CGColor(red: 0.10, green: 0.80, blue: 0.35, alpha: 0.12))
ctx.setLineWidth(3)
ctx.strokePath()

// ECG waveform
let wavePoints: [(CGFloat, CGFloat)] = [
    (140, 580),
    (250, 580),
    (340, 380),
    (470, 720),
    (580, 440),
    (670, 580),
    (884, 580),
]

// Glow layer - thick blurry wave behind
ctx.move(to: CGPoint(x: wavePoints[0].0, y: size - wavePoints[0].1))
for i in 1..<wavePoints.count {
    ctx.addLine(to: CGPoint(x: wavePoints[i].0, y: size - wavePoints[i].1))
}
ctx.setStrokeColor(CGColor(red: 0.10, green: 0.85, blue: 0.35, alpha: 0.35))
ctx.setLineWidth(52)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.strokePath()

// Main wave line
ctx.move(to: CGPoint(x: wavePoints[0].0, y: size - wavePoints[0].1))
for i in 1..<wavePoints.count {
    ctx.addLine(to: CGPoint(x: wavePoints[i].0, y: size - wavePoints[i].1))
}
ctx.setStrokeColor(CGColor(red: 0.20, green: 0.95, blue: 0.45, alpha: 1.0))
ctx.setLineWidth(18)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.strokePath()

// Bright core highlight
ctx.move(to: CGPoint(x: wavePoints[0].0, y: size - wavePoints[0].1))
for i in 1..<wavePoints.count {
    ctx.addLine(to: CGPoint(x: wavePoints[i].0, y: size - wavePoints[i].1))
}
ctx.setStrokeColor(CGColor(red: 0.60, green: 1.0, blue: 0.70, alpha: 0.6))
ctx.setLineWidth(6)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.strokePath()

image.unlockFocus()

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
