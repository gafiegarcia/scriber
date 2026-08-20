import AppKit

// The disk image window's backdrop and its drag arrow.
//
// Finder renders a volume window's labels black whenever a background picture is
// set, whatever the picture holds — so this design is light in both appearances,
// and a dark variant is not available to build. Verified on macOS 27.
//
// The arrow is `arrow.right` from SF Symbols, so it carries the same weight and
// terminals as the system icons it sits between.
func render(scale: CGFloat, to path: String) {
    let width = 660, height = 400
    let w = Int(CGFloat(width) * scale), h = Int(CGFloat(height) * scale)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.scaleBy(x: scale, y: scale)

    ctx.setFillColor(CGColor(red: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let config = NSImage.SymbolConfiguration(pointSize: 46, weight: .medium)
    guard let symbol = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return }

    // Tinted on its own transparent canvas: `sourceAtop` keeps only what it lands
    // on, so run against the backdrop it would fill the whole rectangle instead
    // of the glyph.
    let size = symbol.size
    let tinted = NSImage(size: size, flipped: false) { bounds in
        symbol.draw(in: bounds)
        NSColor(calibratedRed: 0.42, green: 0.42, blue: 0.45, alpha: 1).set()
        bounds.fill(using: .sourceAtop)
        return true
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    // Centred between the two icons, on their shared line. Finder counts y down
    // from the top of the content area; Core Graphics counts up.
    tinted.draw(in: NSRect(x: 330 - size.width / 2,
                           y: CGFloat(height) - 170 - size.height / 2,
                           width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()

    guard let image = ctx.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

let dir = CommandLine.arguments[1]
render(scale: 1, to: "\(dir)/dmg-background.png")
render(scale: 2, to: "\(dir)/dmg-background@2x.png")
print("rendered")
