import AppKit
import QuartzCore

/// Fait voler une miniature de capture, du coin bas-droit de l'écran (là où macOS affiche la sienne)
/// jusqu'à l'encoche.
@MainActor
final class ArrivalAnimator {
    private var window: NSPanel?

    func fly(image: NSImage, screen: NSScreen, target: CGPoint, completion: @escaping () -> Void) {
        window?.orderOut(nil)
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        panel.contentView = view

        let aspect = max(0.5, min(2.4, image.size.width / max(image.size.height, 1)))
        let h: CGFloat = min(150, 230 / aspect)
        let w = h * aspect

        let flyer = CALayer()
        flyer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        flyer.shadowColor = NSColor.black.cgColor
        flyer.shadowOpacity = 0.45
        flyer.shadowRadius = 14
        flyer.shadowOffset = CGSize(width: 0, height: -6)
        let picture = CALayer()
        picture.frame = flyer.bounds
        picture.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        picture.contentsGravity = .resizeAspectFill
        picture.cornerRadius = 10
        picture.masksToBounds = true
        picture.borderWidth = 1
        picture.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        flyer.addSublayer(picture)
        view.layer?.addSublayer(flyer)

        let size = screen.frame.size
        let start = CGPoint(x: size.width - 36 - w / 2, y: 36 + h / 2)
        let end = CGPoint(x: target.x - screen.frame.minX, y: target.y - screen.frame.minY)
        flyer.position = start
        flyer.opacity = 0

        panel.orderFrontRegardless()
        window = panel

        // 1. Apparition en « pop » à l'emplacement de la miniature macOS.
        let pop = CABasicAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.7
        pop.toValue = 1.0
        pop.duration = 0.22
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        flyer.opacity = 1
        flyer.add(pop, forKey: "pop")

        // 2. Vol en arc vers l'encoche, en rétrécissant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            let path = CGMutablePath()
            path.move(to: start)
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x - 40, y: start.y + (end.y - start.y) * 0.55),
                          control2: CGPoint(x: end.x + (start.x - end.x) * 0.55, y: end.y - 90))

            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.0
            shrink.toValue = 0.1
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = -0.2
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.8, 1]

            let group = CAAnimationGroup()
            group.animations = [move, shrink, turn, fade]
            group.duration = 0.7
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0.0, 0.35, 1.0)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            CATransaction.begin()
            CATransaction.setCompletionBlock {
                DispatchQueue.main.async {
                    panel.orderOut(nil)
                    if self?.window === panel { self?.window = nil }
                    completion()
                }
            }
            flyer.position = end
            flyer.opacity = 0
            flyer.add(group, forKey: "fly")
            CATransaction.commit()
        }
    }
}
