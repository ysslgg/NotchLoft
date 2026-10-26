// Génère Resources/AppIcon-1024.png (icône NotchTune). Usage : swift scripts/make-icon.swift <sortie.png>
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

// Vinyle
let vc = CGPoint(x: 512, y: 410), vr: CGFloat = 250
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: col(0, 0, 0, 0.55))
ctx.setFillColor(col(0.05, 0.03, 0.09))
ctx.fillEllipse(in: CGRect(x: vc.x - vr, y: vc.y - vr, width: vr * 2, height: vr * 2))
ctx.restoreGState()
// Sillons
ctx.setLineWidth(1.5)
var r: CGFloat = 105
while r < vr - 6 {
    ctx.setStrokeColor(col(1, 1, 1, 0.06 + 0.04 * CGFloat(Int(r) % 3)))
    ctx.strokeEllipse(in: CGRect(x: vc.x - r, y: vc.y - r, width: r * 2, height: r * 2))
    r += 9
}
// Reflets coniques brillants
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: vc.x - vr, y: vc.y - vr, width: vr * 2, height: vr * 2)); ctx.clip()
for (a0, a1) in [(25.0, 70.0), (205.0, 250.0)] {
    ctx.move(to: vc)
    ctx.addArc(center: vc, radius: vr, startAngle: a0 * .pi / 180, endAngle: a1 * .pi / 180, clockwise: false)
    ctx.closePath()
    ctx.clip()
    ctx.drawRadialGradient(grad([col(1, 1, 1, 0.0), col(1, 1, 1, 0.38), col(1, 1, 1, 0.0)], [0, 0.7, 1]),
                           startCenter: vc, startRadius: 60, endCenter: vc, endRadius: vr, options: [])
    ctx.resetClip()
    ctx.addEllipse(in: CGRect(x: vc.x - vr, y: vc.y - vr, width: vr * 2, height: vr * 2)); ctx.clip()
}
ctx.restoreGState()
// Étiquette centrale
ctx.drawRadialGradient(grad([col(1, 0.55, 0.8), col(0.7, 0.2, 0.75)], [0, 1]),
                       startCenter: CGPoint(x: vc.x - 14, y: vc.y + 14), startRadius: 0,
                       endCenter: vc, endRadius: 92, options: [])
ctx.setFillColor(col(0.07, 0.03, 0.12))
ctx.fillEllipse(in: CGRect(x: vc.x - 14, y: vc.y - 14, width: 28, height: 28))

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
