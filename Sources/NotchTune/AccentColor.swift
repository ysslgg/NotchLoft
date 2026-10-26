import AppKit
import SwiftUI

enum AccentColor {
    static let fallback = NSColor(hue: 0.83, saturation: 0.55, brightness: 1.0, alpha: 1)

    /// Moyenne des pixels pondérée par la saturation, puis rendue vive.
    static func extract(from image: NSImage) -> NSColor {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return fallback }
        let n = 32
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8,
                bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard drawn else { return fallback }

        var sr = 0.0, sg = 0.0, sb = 0.0, sw = 0.0
        var ar = 0.0, ag = 0.0, ab = 0.0
        for i in 0..<(n * n) {
            let r = Double(pixels[i * 4]) / 255
            let g = Double(pixels[i * 4 + 1]) / 255
            let b = Double(pixels[i * 4 + 2]) / 255
            ar += r; ag += g; ab += b
            let mx = max(r, g, b), mn = min(r, g, b)
            guard mx > 0.12 else { continue }
            let s = (mx - mn) / mx
            let w = s * s * mx
            sr += r * w; sg += g * w; sb += b * w; sw += w
        }
        let count = Double(n * n)
        let r: Double, g: Double, b: Double
        if sw > 0.5 {
            r = sr / sw; g = sg / sw; b = sb / sw
        } else {
            r = ar / count; g = ag / count; b = ab / count
        }
        let base = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        base.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        if s < 0.1 {
            // Pochette quasi monochrome : blanc légèrement teinté.
            return NSColor(white: max(0.85, v), alpha: 1)
        }
        return NSColor(hue: h, saturation: min(1, max(0.65, s * 1.2)),
                       brightness: min(1, max(0.88, v * 1.2)), alpha: 1)
    }
}
