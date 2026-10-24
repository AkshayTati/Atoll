import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let plate = NSRect(x: 48, y: 48, width: size - 96, height: size - 96)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 208, yRadius: 208)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.03, alpha: 1)
])!
gradient.draw(in: platePath, angle: -90)

NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
platePath.lineWidth = 4
platePath.stroke()

let island = NSRect(x: size / 2 - 190, y: size - 300, width: 380, height: 116)
let islandPath = NSBezierPath(roundedRect: island, xRadius: 58, yRadius: 58)
NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
islandPath.fill()

let dot = NSBezierPath(ovalIn: NSRect(x: size / 2 + 118, y: size - 268, width: 24, height: 24))
NSColor(calibratedRed: 0.32, green: 0.85, blue: 0.45, alpha: 1).setFill()
dot.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render icon")
}
try! png.write(to: URL(fileURLWithPath: output))
