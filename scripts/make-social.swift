// Image d'aperçu du dépôt (1280×640). Usage : swift make-social.swift <icône.png> <capture.png> <sortie.png>
import AppKit
let a = CommandLine.arguments
let W = 1280, H = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let full = NSRect(x: 0, y: 0, width: W, height: H)
NSGradient(colors: [NSColor(calibratedRed: 0.24, green: 0.09, blue: 0.52, alpha: 1),
                    NSColor(calibratedRed: 0.55, green: 0.20, blue: 0.80, alpha: 1),
                    NSColor(calibratedRed: 0.95, green: 0.42, blue: 0.75, alpha: 1)])!.draw(in: full, angle: -30)

// Capture de l'encoche collée au bord haut ; le fond uni de la capture est rendu transparent.
let shotRep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[2])))!
let c0 = shotRep.colorAt(x: 2, y: 2)!.usingColorSpace(.deviceRGB)!
for y in 0..<shotRep.pixelsHigh {
    for x in 0..<shotRep.pixelsWide {
        guard let c = shotRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        let d = sqrt(pow(c.redComponent - c0.redComponent, 2) + pow(c.greenComponent - c0.greenComponent, 2)
                     + pow(c.blueComponent - c0.blueComponent, 2)) * 255
        let t = min(1, max(0, (d - 14) / 30))
        shotRep.setColor(NSColor(deviceRed: c.redComponent, green: c.greenComponent, blue: c.blueComponent,
                                 alpha: t * t * (3 - 2 * t)), atX: x, y: y)
    }
}
let shot = NSImage(size: NSSize(width: shotRep.pixelsWide, height: shotRep.pixelsHigh))
shot.addRepresentation(shotRep)
let sw: CGFloat = 760, sh = sw * CGFloat(shotRep.pixelsHigh) / CGFloat(shotRep.pixelsWide)
shot.draw(in: NSRect(x: (CGFloat(W) - sw) / 2, y: CGFloat(H) - sh, width: sw, height: sh))

// Icône et textes
NSImage(contentsOfFile: a[1])!.draw(in: NSRect(x: 100, y: 40, width: 230, height: 230))
func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ alpha: CGFloat, at p: NSPoint) {
    (s as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                  .foregroundColor: NSColor.white.withAlphaComponent(alpha)])
}
text("NotchLoft", 92, .heavy, 1, at: NSPoint(x: 350, y: 150))
text("Music, clipboard, screenshots, files: all in your notch.", 33, .medium, 0.9, at: NSPoint(x: 356, y: 100))
text("macOS 14+  ·  Apple Silicon and Intel  ·  Free", 23, .regular, 0.7, at: NSPoint(x: 358, y: 58))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
