// Génère Resources/AppIcon-1024.png (icône NotchLoft). Usage : swift scripts/make-icon.swift <sortie.png>
import AppKit
import CoreGraphics

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
func grad(_ cols: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: locs)! }

// Squircle macOS : 824 pt dans un canvas de 1024 (marges pour l'ombre).
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 184, cornerHeight: 184, transform: nil)

// Ombre portée
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: col(0.1, 0, 0.2, 0.5))
ctx.addPath(squircle); ctx.setFillColor(col(0.4, 0.15, 0.7)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
// Fond violet → rose
ctx.drawLinearGradient(grad([col(0.28, 0.10, 0.62), col(0.55, 0.18, 0.78), col(0.95, 0.38, 0.72)], [0, 0.5, 1]),
                       start: CGPoint(x: 200, y: 924), end: CGPoint(x: 800, y: 100), options: [])
// Lueur douce en bas à droite
ctx.drawRadialGradient(grad([col(1, 0.6, 0.85, 0.55), col(1, 0.6, 0.85, 0)], [0, 1]),
                       startCenter: CGPoint(x: 760, y: 220), startRadius: 0,
                       endCenter: CGPoint(x: 760, y: 220), endRadius: 460, options: [])

// Corde à linge avec trois objets accrochés : une note, un vinyle, une capture d'écran
func peg(_ x: CGFloat, _ y: CGFloat) {
    let r = CGRect(x: x - 14, y: y - 24, width: 28, height: 62)
    let p = CGPath(roundedRect: r, cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: col(0, 0, 0, 0.45))
    ctx.addPath(p); ctx.setFillColor(col(0.97, 0.95, 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.setFillColor(col(0.55, 0.4, 0.75, 0.55))
    ctx.fill(CGRect(x: x - 14, y: y + 6, width: 28, height: 3))
}
let ropeTop: CGFloat = 705
func ropeY(_ x: CGFloat) -> CGFloat {
    let t = (x - 150) / (874 - 150)
    return ropeTop - 4 * 38 * t * (1 - t)
}
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 8, color: col(0, 0, 0, 0.4))
ctx.setStrokeColor(col(1, 0.9, 0.75)); ctx.setLineWidth(8); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 150, y: ropeTop))
ctx.addQuadCurve(to: CGPoint(x: 874, y: ropeTop), control: CGPoint(x: 512, y: ropeTop - 76))
ctx.strokePath()
ctx.restoreGState()

func hang(_ cx: CGFloat, angle: CGFloat, _ draw: () -> Void) {
    let top = ropeY(cx) - 6
    ctx.saveGState()
    ctx.translateBy(x: cx, y: top)
    ctx.rotate(by: angle * .pi / 180)
    ctx.translateBy(x: 0, y: -8)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: col(0, 0, 0, 0.45))
    draw()
    ctx.restoreGState()
}

// Note / presse-papier (à gauche)
hang(280, angle: 5) {
    let r = CGRect(x: -85, y: -225, width: 170, height: 215)
    let p = CGPath(roundedRect: r, cornerWidth: 22, cornerHeight: 22, transform: nil)
    ctx.addPath(p); ctx.setFillColor(col(0.98, 0.96, 1)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setFillColor(col(0.96, 0.45, 0.78))
    ctx.addPath(CGPath(roundedRect: CGRect(x: -62, y: -62, width: 100, height: 20), cornerWidth: 10, cornerHeight: 10, transform: nil)); ctx.fillPath()
    ctx.setFillColor(col(0.55, 0.4, 0.8, 0.35))
    for (i, w) in [124, 110, 124, 80].enumerated() {
        ctx.addPath(CGPath(roundedRect: CGRect(x: -62, y: -105 - CGFloat(i) * 28, width: CGFloat(w), height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil)); ctx.fillPath()
    }
}
// Vinyle (au centre)
hang(512, angle: -2) {
    let c = CGPoint(x: 0, y: -135), rr: CGFloat = 130
    ctx.setFillColor(col(0.05, 0.03, 0.09))
    ctx.fillEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setLineWidth(1.5)
    var g: CGFloat = 52
    while g < rr - 6 {
        ctx.setStrokeColor(col(1, 1, 1, 0.07))
        ctx.strokeEllipse(in: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2))
        g += 8
    }
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)); ctx.clip()
    for (a0, a1) in [(25.0, 70.0), (205.0, 250.0)] {
        ctx.move(to: c)
        ctx.addArc(center: c, radius: rr, startAngle: a0 * .pi / 180, endAngle: a1 * .pi / 180, clockwise: false)
        ctx.closePath(); ctx.clip()
        ctx.drawRadialGradient(grad([col(1, 1, 1, 0.0), col(1, 1, 1, 0.36), col(1, 1, 1, 0.0)], [0, 0.7, 1]),
                               startCenter: c, startRadius: 30, endCenter: c, endRadius: rr, options: [])
        ctx.resetClip()
        ctx.addEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)); ctx.clip()
    }
    ctx.restoreGState()
    ctx.drawRadialGradient(grad([col(1, 0.55, 0.8), col(0.7, 0.2, 0.75)], [0, 1]),
                           startCenter: CGPoint(x: c.x - 8, y: c.y + 8), startRadius: 0, endCenter: c, endRadius: 46, options: [])
    ctx.setFillColor(col(0.07, 0.03, 0.12))
    ctx.fillEllipse(in: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16))
}
// Capture d'écran (à droite)
hang(744, angle: -5) {
    let r = CGRect(x: -88, y: -215, width: 176, height: 205)
    let p = CGPath(roundedRect: r, cornerWidth: 22, cornerHeight: 22, transform: nil)
    ctx.saveGState()
    ctx.addPath(p); ctx.clip()
    ctx.drawLinearGradient(grad([col(0.35, 0.78, 1), col(0.55, 0.45, 0.98)], [0, 1]),
                           start: CGPoint(x: 0, y: -10), end: CGPoint(x: 0, y: -215), options: [])
    ctx.setFillColor(col(1, 0.95, 0.7))
    ctx.fillEllipse(in: CGRect(x: 18, y: -85, width: 40, height: 40))
    ctx.setFillColor(col(0.2, 0.15, 0.5, 0.85))
    ctx.move(to: CGPoint(x: -88, y: -215)); ctx.addLine(to: CGPoint(x: -88, y: -160))
    ctx.addLine(to: CGPoint(x: -35, y: -108)); ctx.addLine(to: CGPoint(x: 5, y: -150))
    ctx.addLine(to: CGPoint(x: 40, y: -125)); ctx.addLine(to: CGPoint(x: 88, y: -175))
    ctx.addLine(to: CGPoint(x: 88, y: -215)); ctx.closePath(); ctx.fillPath()
    ctx.restoreGState()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(p); ctx.setStrokeColor(col(1, 1, 1, 0.9)); ctx.setLineWidth(7); ctx.strokePath()
}
peg(280, ropeY(280)); peg(512, ropeY(512)); peg(744, ropeY(744))

// Mixeur : trois curseurs verticaux en bas
for (i, (x, v)) in [(330.0, 0.65), (512.0, 0.35), (694.0, 0.8)].enumerated() {
    _ = i
    let h: CGFloat = 130, y0: CGFloat = 175
    let track = CGPath(roundedRect: CGRect(x: x - 11, y: y0, width: 22, height: h), cornerWidth: 11, cornerHeight: 11, transform: nil)
    ctx.addPath(track); ctx.setFillColor(col(1, 1, 1, 0.22)); ctx.fillPath()
    let fillH = h * CGFloat(v)
    ctx.addPath(CGPath(roundedRect: CGRect(x: x - 11, y: y0, width: 22, height: fillH), cornerWidth: 11, cornerHeight: 11, transform: nil))
    ctx.setFillColor(col(1, 0.62, 0.88)); ctx.fillPath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 6, color: col(0, 0, 0, 0.4))
    ctx.setFillColor(col(1, 1, 1))
    ctx.fillEllipse(in: CGRect(x: x - 21, y: y0 + fillH - 21, width: 42, height: 42))
    ctx.restoreGState()
}

// Encoche noire en haut (forme avec oreilles concaves)
let nw: CGFloat = 470, nh: CGFloat = 150, ear: CGFloat = 34, br: CGFloat = 56
let nx = 512 - nw / 2, top = body.maxY
let n = CGMutablePath()
n.move(to: CGPoint(x: nx - ear, y: top))
n.addQuadCurve(to: CGPoint(x: nx, y: top - ear), control: CGPoint(x: nx, y: top))
n.addLine(to: CGPoint(x: nx, y: top - nh + br))
n.addQuadCurve(to: CGPoint(x: nx + br, y: top - nh), control: CGPoint(x: nx, y: top - nh))
n.addLine(to: CGPoint(x: nx + nw - br, y: top - nh))
n.addQuadCurve(to: CGPoint(x: nx + nw, y: top - nh + br), control: CGPoint(x: nx + nw, y: top - nh))
n.addLine(to: CGPoint(x: nx + nw, y: top - ear))
n.addQuadCurve(to: CGPoint(x: nx + nw + ear, y: top), control: CGPoint(x: nx + nw, y: top))
n.closeSubpath()
ctx.addPath(n); ctx.setFillColor(col(0, 0, 0)); ctx.fillPath()

// Barres roses lumineuses dans l'encoche
let heights: [CGFloat] = [34, 64, 92, 52, 76]
let bw: CGFloat = 20, gap: CGFloat = 22
let total = CGFloat(heights.count) * bw + CGFloat(heights.count - 1) * gap
var bx = 512 - total / 2
let cy = top - nh / 2 - 8
for h in heights {
    let rect = CGRect(x: bx, y: cy - h / 2, width: bw, height: h)
    let p = CGPath(roundedRect: rect, cornerWidth: bw / 2, cornerHeight: bw / 2, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 28, color: col(1, 0.3, 0.7, 0.95))
    ctx.addPath(p); ctx.setFillColor(col(1, 0.42, 0.78)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(p); ctx.setFillColor(col(1, 0.6, 0.88)); ctx.fillPath()
    bx += bw + gap
}

// Reflet de verre sur la moitié haute
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
ctx.drawLinearGradient(grad([col(1, 1, 1, 0.16), col(1, 1, 1, 0)], [0, 1]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
ctx.restoreGState()
// Liseré clair intérieur
ctx.setLineWidth(3)
ctx.addPath(squircle); ctx.setStrokeColor(col(1, 1, 1, 0.22)); ctx.strokePath()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
