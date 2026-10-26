import AppKit

/// Dimensions de l'encoche physique (ou simulée) et tailles des deux modes.
struct NotchGeometry: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasHardwareNotch: Bool

    static let compactSide: CGFloat = 32
    static let expandedSize = CGSize(width: 330, height: 160)
    /// Fenêtre fixe, un peu plus grande que le mode survol.
    static let panelSize = CGSize(width: 380, height: 180)

    var compactSize: CGSize { CGSize(width: notchWidth + 2 * Self.compactSide, height: notchHeight) }

    /// Écran portant l'encoche, sinon l'écran de la barre des menus (encoche simulée).
    static func resolve() -> (screen: NSScreen, geometry: NotchGeometry)? {
        if let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            let left = s.auxiliaryTopLeftArea?.width ?? 0
            let right = s.auxiliaryTopRightArea?.width ?? 0
            let w = s.frame.width - left - right
            if w > 0 {
                return (s, NotchGeometry(notchWidth: w, notchHeight: s.safeAreaInsets.top, hasHardwareNotch: true))
            }
        }
        guard let s = NSScreen.screens.first else { return nil }
        let menuBar = s.frame.maxY - s.visibleFrame.maxY
        return (s, NotchGeometry(notchWidth: 185, notchHeight: max(24, menuBar), hasHardwareNotch: false))
    }
}
