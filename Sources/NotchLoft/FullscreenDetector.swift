import AppKit
import CoreGraphics

// API privée de macOS (SkyLight), utilisée par de nombreuses apps de barre des menus : elle seule indique
// si l'écran affiche une app en plein écran. Si elle disparaissait, `isFullscreen` resterait simplement faux.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray?

/// Vrai quand l'écran de l'encoche affiche une app en plein écran.
final class FullscreenDetector: ObservableObject {
    static let shared = FullscreenDetector()

    @Published private(set) var isFullscreen = false
    private var timer: Timer?

    func start() {
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
                // La transition vers le plein écran dure environ une seconde.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.refresh() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self?.refresh() }
            }
        }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let now = Self.currentSpaceIsFullscreen()
        if now != isFullscreen { isFullscreen = now }
    }

    private static func displayUUID(of screen: NSScreen?) -> String? {
        guard let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    private static func currentSpaceIsFullscreen() -> Bool {
        guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] else { return false }
        let target = displayUUID(of: NotchGeometry.resolve()?.screen)
        let display = displays.first { ($0["Display Identifier"] as? String) == target } ?? displays.first
        let current = display?["Current Space"] as? [String: Any]
        return (current?["type"] as? Int) == 4        // 0 = bureau normal, 4 = app en plein écran
    }
}
