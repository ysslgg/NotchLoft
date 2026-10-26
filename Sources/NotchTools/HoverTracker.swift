import AppKit
import SwiftUI

/// Position de la souris dans les coordonnées de la fenêtre de l'encoche (origine en haut à gauche).
/// Alimentée par le suivi de souris du contrôleur : `onHover` de SwiftUI reste muet tant que l'app
/// n'est pas active, ce qui est toujours le cas ici (ni Dock, ni fenêtre au premier plan).
final class MouseHub: ObservableObject {
    static let shared = MouseHub()
    @Published var location = CGPoint(x: -10_000, y: -10_000)
}

private struct HoverTracker: View {
    let onChange: (Bool) -> Void
    @ObservedObject private var hub = MouseHub.shared
    @StateObject private var state = HoverBox()

    var body: some View {
        GeometryReader { g in
            Color.clear
                .onChange(of: hub.location) { _, p in
                    let inside = g.frame(in: .global).contains(p)
                    guard inside != state.on else { return }
                    state.on = inside
                    onChange(inside)
                }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func hoverAlways(_ onChange: @escaping (Bool) -> Void) -> some View {
        background(HoverTracker(onChange: onChange))
    }
}
