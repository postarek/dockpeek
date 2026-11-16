// Renders the DockPeek icon as a 1024px PNG. Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824px rounded square centered on a 1024 canvas.
let inset: CGFloat = 100
let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.current?.restoreGraphicsState()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.70, green: 0.32, blue: 0.92, alpha: 1),
])!
gradient.draw(in: shape, angle: 90)

// Preview card floating above a dock bar.
NSColor.white.withAlphaComponent(0.95).setFill()
NSBezierPath(roundedRect: NSRect(x: 300, y: 470, width: 424, height: 280), xRadius: 36, yRadius: 36).fill()
NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.95, alpha: 0.35).setFill()
NSBezierPath(roundedRect: NSRect(x: 330, y: 500, width: 364, height: 190), xRadius: 18, yRadius: 18).fill()
for (i, alpha) in [0.9, 0.6, 0.4].enumerated() {
    NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.95, alpha: alpha).setFill()
    NSBezierPath(ovalIn: NSRect(x: 336 + CGFloat(i) * 32, y: 706, width: 20, height: 20)).fill()
}
// Pointer triangle from card to dock icon.
let pointer = NSBezierPath()
pointer.move(to: NSPoint(x: 472, y: 472))
pointer.line(to: NSPoint(x: 552, y: 472))
pointer.line(to: NSPoint(x: 512, y: 425))
pointer.close()
NSColor.white.withAlphaComponent(0.95).setFill()
pointer.fill()

NSColor.white.withAlphaComponent(0.35).setFill()
NSBezierPath(roundedRect: NSRect(x: 210, y: 220, width: 604, height: 150), xRadius: 40, yRadius: 40).fill()
for i in 0..<5 {
    let x = 236 + CGFloat(i) * 116
    NSColor.white.withAlphaComponent(i == 2 ? 1 : 0.7).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: 251, width: 88, height: 88), xRadius: 20, yRadius: 20).fill()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
