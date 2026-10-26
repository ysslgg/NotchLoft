import AppKit

/// Version monochrome (template) du logo : encoche avec ses barres au-dessus d'un vinyle.
enum MenuBarIcon {
    /// `badge` ajoute une pastille quand une mise à jour est disponible.
    static func make(badge: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Contour de l'icône
            let frame = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.2, width: 16, height: 15.6),
                                     xRadius: 4.4, yRadius: 4.4)
            frame.lineWidth = 1.3
            frame.stroke()

            // Encoche pleine, collée au bord haut, avec oreilles concaves
            let nx: CGFloat = 4.6, nw: CGFloat = 9.8, top: CGFloat = 16.8, nh: CGFloat = 5.6
            let ear: CGFloat = 1.5, br: CGFloat = 2.2
            let n = NSBezierPath()
            n.move(to: NSPoint(x: nx - ear, y: top))
            n.curve(to: NSPoint(x: nx, y: top - ear),
                    controlPoint1: NSPoint(x: nx - ear * 0.2, y: top), controlPoint2: NSPoint(x: nx, y: top - ear * 0.2))
            n.line(to: NSPoint(x: nx, y: top - nh + br))
            n.curve(to: NSPoint(x: nx + br, y: top - nh),
                    controlPoint1: NSPoint(x: nx, y: top - nh + br * 0.3), controlPoint2: NSPoint(x: nx + br * 0.3, y: top - nh))
            n.line(to: NSPoint(x: nx + nw - br, y: top - nh))
            n.curve(to: NSPoint(x: nx + nw, y: top - nh + br),
                    controlPoint1: NSPoint(x: nx + nw - br * 0.3, y: top - nh), controlPoint2: NSPoint(x: nx + nw, y: top - nh + br * 0.3))
            n.line(to: NSPoint(x: nx + nw, y: top - ear))
            n.curve(to: NSPoint(x: nx + nw + ear, y: top),
                    controlPoint1: NSPoint(x: nx + nw, y: top - ear * 0.2), controlPoint2: NSPoint(x: nx + nw + ear * 0.2, y: top))
            n.close()
            n.fill()

            // Barres découpées dans l'encoche
            NSGraphicsContext.current?.compositingOperation = .clear
            let heights: [CGFloat] = [1.8, 3.1, 4.0, 2.4, 3.4]
            let bw: CGFloat = 0.85, gap: CGFloat = 0.95
            let total = CGFloat(heights.count) * bw + CGFloat(heights.count - 1) * gap
            var x = nx + (nw - total) / 2
            let cy = top - nh / 2 - 0.2
            for h in heights {
                NSBezierPath(roundedRect: NSRect(x: x, y: cy - h / 2, width: bw, height: h),
                             xRadius: bw / 2, yRadius: bw / 2).fill()
                x += bw + gap
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            // Corde à linge avec trois objets : une note, un vinyle, une capture
            let ropeY: CGFloat = 9.4
            let rope = NSBezierPath()
            rope.move(to: NSPoint(x: 4.2, y: ropeY + 0.4))
            rope.curve(to: NSPoint(x: 14.8, y: ropeY + 0.4),
                       controlPoint1: NSPoint(x: 7.5, y: ropeY - 0.9), controlPoint2: NSPoint(x: 11.5, y: ropeY - 0.9))
            rope.lineWidth = 0.9
            rope.lineCapStyle = .round
            rope.stroke()
            // note (rectangle)
            NSBezierPath(roundedRect: NSRect(x: 4.5, y: 4.4, width: 3.2, height: 4.6), xRadius: 0.8, yRadius: 0.8).fill()
            // vinyle (disque)
            NSBezierPath(ovalIn: NSRect(x: 7.85, y: 4.9, width: 3.5, height: 3.5)).fill()
            // capture (rectangle)
            NSBezierPath(roundedRect: NSRect(x: 11.5, y: 4.4, width: 3.2, height: 4.6), xRadius: 0.8, yRadius: 0.8).fill()
            // pinces
            for x in [6.1, 9.6, 13.1] as [CGFloat] {
                NSBezierPath(roundedRect: NSRect(x: x - 0.5, y: 8.2, width: 1.0, height: 2.4), xRadius: 0.4, yRadius: 0.4).fill()
            }
            if badge {
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 12.2, y: 11.2, width: 7.6, height: 7.6)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: NSRect(x: 13.4, y: 12.4, width: 5.2, height: 5.2)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
