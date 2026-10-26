import SwiftUI

@MainActor
final class NotchUIState: ObservableObject {
    @Published var expanded = false
    @Published var isScrubbing = false
    @Published var scrubFraction: Double?
    @Published var geometry = NotchGeometry(notchWidth: 185, notchHeight: 32, hasHardwareNotch: false)
}

private enum Anim {
    static let shape = Animation.spring(response: 0.36, dampingFraction: 0.84)
    // Contenu compact : disparaît vite à l'ouverture, revient avec un délai à la fermeture.
    static let compactIn = Animation.easeOut(duration: 0.18).delay(0.22)
    static let compactOut = Animation.easeOut(duration: 0.08)
    // Contenu étendu : léger délai à l'ouverture, disparaît vite à la fermeture.
    static let expandedIn = Animation.easeOut(duration: 0.2).delay(0.1)
    static let expandedOut = Animation.easeOut(duration: 0.08)
}

struct NotchRootView: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var ui: NotchUIState

    var body: some View {
        let g = ui.geometry
        let show = model.hasTrack
        let size: CGSize = show
            ? (ui.expanded ? NotchGeometry.expandedSize : g.compactSize)
            : CGSize(width: g.notchWidth, height: g.notchHeight)
        let shape = NotchShape(topRadius: ui.expanded ? 14 : 6, bottomRadius: ui.expanded ? 24 : 10)

        ZStack(alignment: .top) {
            Color.clear
            ZStack(alignment: .top) {
                Color.black
                LinearGradient(colors: [model.accent.opacity(0), model.accent.opacity(0.24)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(ui.expanded ? 1 : 0.4)

                CompactContent(model: model, geometry: g)
                    .frame(width: g.compactSize.width, height: g.compactSize.height)
                    .opacity(ui.expanded || !show ? 0 : 1)
                    .animation(ui.expanded ? Anim.compactOut : Anim.compactIn, value: ui.expanded)
                    .animation(.easeOut(duration: 0.2), value: show)

                ExpandedContent(model: model, ui: ui)
                    .frame(width: NotchGeometry.expandedSize.width, height: NotchGeometry.expandedSize.height)
                    .opacity(ui.expanded && show ? 1 : 0)
                    .animation(ui.expanded ? Anim.expandedIn : Anim.expandedOut, value: ui.expanded)
                    .allowsHitTesting(ui.expanded)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            // Sur un Mac sans encoche, la forme simulée disparaît quand rien ne joue.
            .opacity(show || g.hasHardwareNotch ? 1 : 0)
            .animation(Anim.shape, value: ui.expanded)
            .animation(Anim.shape, value: show)
            .animation(.easeOut(duration: 0.25), value: g)
        }
        .frame(width: NotchGeometry.panelSize.width, height: NotchGeometry.panelSize.height, alignment: .top)
    }
}

// MARK: - Mode compact

private struct CompactContent: View {
    @ObservedObject var model: NowPlayingModel
    let geometry: NotchGeometry

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(image: model.artwork, size: 20, radius: 5, accent: model.accent, halo: false)
                .padding(.leading, 9)
            Spacer(minLength: 0)
            Group {
                if model.isPlaying {
                    VisualizerBars(color: model.accent, playing: true)
                } else {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(model.accent)
                }
            }
            .frame(width: 18, height: 18)
            .padding(.trailing, 9)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Mode survol

private struct ExpandedContent: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var ui: NotchUIState

    private var fraction: Double {
        if let f = ui.scrubFraction { return f }
        return model.duration > 0 ? model.position / model.duration : 0
    }
    private var shownPosition: Double { ui.scrubFraction.map { $0 * model.duration } ?? model.position }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: ui.geometry.notchHeight + 2)

            HStack(spacing: 12) {
                ArtworkView(image: model.artwork, size: 46, radius: 9, accent: model.accent, halo: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(model.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 4)

            ProgressBar(fraction: fraction, accent: model.accent,
                        onChange: { f in
                            ui.scrubFraction = f
                            ui.isScrubbing = true
                        },
                        onEnd: { f in
                            model.seek(toFraction: f)
                            ui.scrubFraction = nil
                            ui.isScrubbing = false
                        })
                .frame(height: 14)

            HStack {
                Text(Self.format(shownPosition))
                Spacer()
                Text(Self.format(model.duration))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 30) {
                ControlButton(symbol: "backward.fill", size: 16) { model.previous() }
                ControlButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", size: 22) { model.togglePlayPause() }
                ControlButton(symbol: "forward.fill", size: 16) { model.next() }
            }
            .frame(height: 30)
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 30)
    }

    static func format(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

private struct ProgressBar: View {
    let fraction: Double
    let accent: Color
    let onChange: (Double) -> Void
    let onEnd: (Double) -> Void

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                Capsule().fill(accent)
                    .frame(width: max(4, g.size.width * min(max(fraction, 0), 1)), height: 4)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in onChange(clamp(v.location.x / g.size.width)) }
                    .onEnded { v in onEnd(clamp(v.location.x / g.size.width)) }
            )
        }
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Éléments communs

private struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat
    let accent: Color
    let halo: Bool

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: halo ? accent.opacity(0.65) : .clear, radius: halo ? 10 : 0)
    }
}

/// Visualiseur décoratif : 5 barres fines animées (aucune capture audio).
struct VisualizerBars: View {
    let color: Color
    let playing: Bool

    private let speeds: [Double] = [5.1, 7.3, 4.2, 6.4, 5.7]
    private let phases: [Double] = [0, 1.7, 3.1, 4.4, 2.2]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let a = sin(t * speeds[i] + phases[i])
                    let b = sin(t * speeds[i] * 0.53 + phases[i] * 1.9)
                    let level = 0.5 + 0.5 * (0.6 * a + 0.4 * b)
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: 4 + 12 * level)
                }
            }
        }
    }
}


private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 0.9)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}
