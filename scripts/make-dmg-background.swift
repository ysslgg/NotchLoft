// Fond du DMG (clair, violet, flèche). Usage : swift make-dmg-background.swift <sortie.png> <échelle>
import AppKit
import CoreGraphics

let out = CommandLine.arguments[1]
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let W: CGFloat = 660, H: CGFloat = 400
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: scale, y: scale)
func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
let g = CGGradient(colorsSpace: cs, colors: [col(0.97, 0.94, 1.0), col(0.90, 0.84, 0.99)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [col(0.8, 0.6, 1, 0.45), col(0.8, 0.6, 1, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 560, y: 340), startRadius: 0, endCenter: CGPoint(x: 560, y: 340), endRadius: 260, options: [])

// Flèche entre l'app (x=170) et Applications (x=490), à y=200 (repère haut-gauche => y' = H-200)
let y = H - 200
let a = CGMutablePath()
a.move(to: CGPoint(x: 252, y: y))
a.addLine(to: CGPoint(x: 392, y: y))
ctx.setLineWidth(7); ctx.setLineCap(.round)
ctx.setStrokeColor(col(0.55, 0.28, 0.85, 0.9))
ctx.addPath(a); ctx.strokePath()
let head = CGMutablePath()
head.move(to: CGPoint(x: 372, y: y + 20)); head.addLine(to: CGPoint(x: 400, y: y)); head.addLine(to: CGPoint(x: 372, y: y - 20))
ctx.setLineJoin(.round)
ctx.addPath(head); ctx.strokePath()

let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.15, blue: 0.6, alpha: 0.9)]
let text = "Glisse NotchTune dans Applications" as NSString
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let size = text.size(withAttributes: attrs)
text.draw(at: CGPoint(x: (W - size.width) / 2, y: 40), withAttributes: attrs)
NSGraphicsContext.restoreGraphicsState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: W, height: H)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
