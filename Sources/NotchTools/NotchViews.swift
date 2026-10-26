import SwiftUI

@MainActor
final class NotchUIState: ObservableObject {
    @Published var expanded = false
    @Published var isScrubbing = false
    @Published var scrubFraction: Double?
    @Published var geometry = NotchGeometry(notchWidth: 185, notchHeight: 32, hasHardwareNotch: false)
    @Published var page: NotchPage = NotchPage(rawValue: UserDefaults.standard.string(forKey: "lastPage") ?? "") ?? .music {
        didSet { UserDefaults.standard.set(page.rawValue, forKey: "lastPage") }
    }

    /// Page réellement affichée (la musique si l'outil a été désactivé).
    var effectivePage: NotchPage { page.isEnabled ? page : .music }
    var pageSize: CGSize { effectivePage.size }
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
    let tools: ToolsHub

    var body: some View {
        let g = ui.geometry
        let musicShown = model.isShown
        let open = ui.expanded
        let size: CGSize = open
            ? ui.pageSize
            : (musicShown ? g.compactSize : CGSize(width: g.notchWidth, height: g.notchHeight))
        let shape = NotchShape(topRadius: open ? 14 : 6, bottomRadius: open ? 24 : 10)

        ZStack(alignment: .top) {
            Color.clear
            ZStack(alignment: .top) {
                Color.black
                LinearGradient(stops: [.init(color: model.accent.opacity(0), location: 0),
                                       .init(color: model.accent.opacity(0), location: 0.22),
                                       .init(color: model.accent.opacity(0.42), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(open ? 1 : 0.35)

                CompactContent(model: model, geometry: g)
                    .frame(width: g.compactSize.width, height: g.compactSize.height)
                    .opacity(open || !musicShown ? 0 : 1)
                    .animation(open ? Anim.compactOut : Anim.compactIn, value: open)
                    .animation(.easeOut(duration: 0.2), value: musicShown)

                ZStack(alignment: .top) {
                    switch ui.effectivePage {
                    case .music:
                        Group {
                            if model.hasTrack {
                                ExpandedContent(model: model, ui: ui)
                            } else {
                                MusicPlaceholder(ui: ui)
                            }
                        }
                        .transition(.opacity)
                    case .clipboard:
                        ClipboardPage(store: tools.clipboard, ui: ui, accent: model.accent).transition(.opacity)
                    case .shelf:
                        ShelfPage(shelf: tools.shelf, ui: ui, accent: model.accent).transition(.opacity)
                    case .audio:
                        AudioPage(mixer: tools.audio, ui: ui, accent: model.accent).transition(.opacity)
                    }
                }
                .frame(width: ui.pageSize.width, height: ui.pageSize.height, alignment: .top)
                .animation(.easeOut(duration: 0.18), value: ui.effectivePage)
                .opacity(open ? 1 : 0)
                .animation(open ? Anim.expandedIn : Anim.expandedOut, value: open)
                .allowsHitTesting(open)

                PageTabs(ui: ui, accent: model.accent)
                    .frame(width: ui.pageSize.width)
                    .opacity(open ? 1 : 0)
                    .animation(open ? Anim.expandedIn : Anim.expandedOut, value: open)
                    .allowsHitTesting(open)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            // Sur un Mac sans encoche, la forme simulée disparaît quand il n'y a rien à montrer.
            .opacity(musicShown || open || g.hasHardwareNotch ? 1 : 0)
            .animation(Anim.shape, value: open)
            .animation(Anim.shape, value: musicShown)
            .animation(Anim.shape, value: ui.effectivePage)
            .animation(.easeOut(duration: 0.25), value: g)
        }
        .frame(width: NotchGeometry.panelSize.width, height: NotchGeometry.panelSize.height, alignment: .top)
    }
}

private struct MusicPlaceholder: View {
    @ObservedObject var ui: NotchUIState
    var body: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: ui.geometry.notchHeight)
            Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.white.opacity(0.35))
            Text("Aucune lecture en cours").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
    }
}

// MARK: - Mode compact

final class HoverBox: ObservableObject {
    @Published var on = false
}

private struct CompactContent: View {
    @ObservedObject var model: NowPlayingModel
    let geometry: NotchGeometry

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                // Bague de progression discrète autour de la pochette
                if Settings.shared.showProgressRing {
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .trim(from: 0, to: model.duration > 0 ? min(1, model.position / model.duration) : 0)
                    .stroke(model.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(0))
                    .animation(.linear(duration: 0.25), value: model.position)
                }
                ArtworkView(image: model.artwork, size: 18, radius: 4.5, accent: model.accent,
                            halo: model.isPlaying ? 0.45 : 0)
                    .opacity(model.isPlaying ? 1 : 0.55)
            }
            // Logo de l'app source (Spotify, Musique…) en pastille sur la pochette
            .overlay(alignment: .bottomTrailing) {
                if let icon = model.sourceIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 11, height: 11)
                        .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(.black, lineWidth: 1))
                        .offset(x: 2, y: 3)
                        .opacity(model.isPlaying ? 1 : 0.6)
                }
            }
            .frame(width: 24, height: 24)
            .padding(.leading, 12)
            Spacer(minLength: 0)
            ZStack {
                VisualizerBars(color: model.accent, playing: model.isPlaying && Settings.shared.showVisualizer)
                    .opacity(model.isPlaying && Settings.shared.showVisualizer ? 1 : 0)
                    .scaleEffect(model.isPlaying ? 1 : 0.6)
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(model.accent)
                    .opacity(model.isPlaying ? 0 : 1)
                    .scaleEffect(model.isPlaying ? 0.6 : 1)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.isPlaying)
            .frame(width: 18, height: 18)
            .padding(.trailing, 12)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeOut(duration: 0.25), value: model.isPlaying)
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
            Spacer().frame(height: ui.geometry.notchHeight + 1)

            HStack(spacing: 12) {
                ArtworkView(image: model.artwork, size: 48, radius: 10, accent: model.accent,
                            halo: model.isPlaying ? 0.7 : 0.15)
                    .scaleEffect(model.isPlaying ? 1 : 0.92)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.isPlaying)
                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(text: model.title, font: .systemFont(ofSize: 14, weight: .semibold),
                                color: .white)
                    MarqueeText(text: model.artist, font: .systemFont(ofSize: 12, weight: .regular),
                                color: NSColor.white.withAlphaComponent(0.6))
                }
                .id(model.title + "\u{1}" + model.artist)
                .transition(.opacity.combined(with: .offset(y: 5)))
                .frame(height: 38)
                if let icon = model.sourceIcon {
                    SourceButton(icon: icon) { model.openSourceApp() }
                }
            }
            .animation(.easeOut(duration: 0.28), value: model.title)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 2)

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
                Text("-" + Self.format(max(0, model.duration - shownPosition)))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 18) {
                ControlButton(symbol: "backward.fill", size: 15, diameter: 32, filled: false) { model.previous() }
                ControlButton(symbol: model.isPlaying ? "pause.fill" : "play.fill", size: 16,
                              diameter: 34, filled: true) { model.togglePlayPause() }
                ControlButton(symbol: "forward.fill", size: 15, diameter: 32, filled: false) { model.next() }
            }
            .frame(height: 34)
            .padding(.top, 3)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 30)
        .background(alignment: .top) {
            // Fond flou tiré de la pochette
            if let img = model.artwork, Settings.shared.blurBackdrop {
                Image(nsImage: img)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: NotchPage.music.size.width, height: 160)
                    .blur(radius: 34)
                    .saturation(1.3)
                    .opacity(0.34)
                    .clipped()
                    // Noir pur à hauteur de l'encoche, puis fondu progressif vers la couleur
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                 .init(color: .clear, location: (ui.geometry.notchHeight + 2) / 160),
                                                 .init(color: .black, location: 0.85)],
                                         startPoint: .top, endPoint: .bottom))
                    .id(model.title)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: model.title)
    }

    static func format(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

/// Texte qui défile en boucle (avec fondu sur les bords) lorsqu'il dépasse la largeur disponible.
private struct MarqueeText: View {
    let text: String
    let font: NSFont
    let color: NSColor

    private let gap: CGFloat = 36
    private let speed: Double = 32

    var body: some View {
        GeometryReader { geo in
            let textW = (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 1
            if textW <= geo.size.width {
                label.frame(width: geo.size.width, alignment: .leading)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { ctx in
                    let travel = textW + gap
                    let cycle = travel / speed + 2.0
                    let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                    let x = -CGFloat(max(0, t - 1.0) * speed).clamped(to: 0...travel)
                    HStack(spacing: gap) { label; label }
                        .fixedSize()
                        .offset(x: x)
                        .frame(width: geo.size.width, alignment: .leading)
                }
                .mask(
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black, location: 0.04),
                                           .init(color: .black, location: 0.92),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                )
            }
        }
        .frame(height: font.pointSize + 5)
    }

    private var label: some View {
        Text(text).font(Font(font)).foregroundStyle(Color(nsColor: color)).lineLimit(1).fixedSize()
    }
}

private extension CGFloat {
    func clamped(to r: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, r.lowerBound), r.upperBound) }
}

private struct ProgressBar: View {
    let fraction: Double
    let accent: Color
    let onChange: (Double) -> Void
    let onEnd: (Double) -> Void
    @StateObject private var hover = HoverBox()
    @StateObject private var drag = HoverBox()

    var body: some View {
        GeometryReader { g in
            let f = min(max(fraction, 0), 1)
            let active = hover.on || drag.on
            let h: CGFloat = active ? 7 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: h)
                Capsule().fill(LinearGradient(colors: [accent.opacity(0.75), accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(h, g.size.width * f), height: h)
                Circle().fill(.white)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: min(max(0, g.size.width * f - 5.5), g.size.width - 11))
                    .scaleEffect(active ? 1 : 0.01)
                    .opacity(active ? 1 : 0)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .hoverAlways { hover.on = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        drag.on = true
                        onChange(clamp(v.location.x / g.size.width))
                    }
                    .onEnded { v in
                        drag.on = false
                        onEnd(clamp(v.location.x / g.size.width))
                    }
            )
        }
    }

    private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let diameter: CGFloat
    let filled: Bool
    let action: () -> Void
    @StateObject private var hover = HoverBox()

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(filled ? Color.white : Color.white.opacity(hover.on ? 0.16 : 0))
                    .scaleEffect(filled && hover.on ? 1.08 : 1)
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(filled ? Color.black : Color.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .hoverAlways { hover.on = $0 }
        .animation(.easeOut(duration: 0.15), value: hover.on)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Éléments communs

private struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat
    let accent: Color
    /// Intensité du halo coloré (0 = aucun).
    let halo: Double

    var body: some View {
        ZStack {
            Color.white.opacity(0.12)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: image.map(ObjectIdentifier.init))
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: accent.opacity(halo), radius: halo > 0 ? 12 : 0)
        .animation(.easeOut(duration: 0.4), value: halo)
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
            .shadow(color: color.opacity(0.6), radius: 3)
        }
    }
}

/// Icône de l'app qui joue ; un clic l'ouvre.
private struct SourceButton: View {
    let icon: NSImage
    let action: () -> Void
    @StateObject private var hover = HoverBox()

    var body: some View {
        Button(action: action) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .opacity(hover.on ? 1 : 0.65)
                .scaleEffect(hover.on ? 1.12 : 1)
        }
        .buttonStyle(PressStyle())
        .hoverAlways { hover.on = $0 }
        .animation(.easeOut(duration: 0.15), value: hover.on)
        .help("Ouvrir l'app")
    }
}
