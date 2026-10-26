import AppKit
import CoreAudio
import SwiftUI

// MARK: - Onglets (dans les « ailes » de part et d'autre de l'encoche physique)

struct PageTabs: View {
    @ObservedObject var ui: NotchUIState
    let accent: Color

    var body: some View {
        let pages = NotchPage.enabled
        if pages.count > 1 {
            let half = (pages.count + 1) / 2
            HStack(spacing: 0) {
                HStack(spacing: 1) { ForEach(Array(pages.prefix(half))) { tab($0) } }
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Spacer().frame(width: ui.geometry.notchWidth + 6)
                HStack(spacing: 1) { ForEach(Array(pages.dropFirst(half))) { tab($0) } }
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 22)
            .frame(height: ui.geometry.notchHeight)
        }
    }

    private func tab(_ page: NotchPage) -> some View {
        TabButton(page: page, selected: ui.effectivePage == page, accent: accent) { ui.page = page }
    }
}

private struct TabButton: View {
    let page: NotchPage
    let selected: Bool
    let accent: Color
    let action: () -> Void
    @StateObject private var hover = HoverBox()

    var body: some View {
        Button(action: action) {
            Image(systemName: page.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? accent : .white.opacity(hover.on ? 0.9 : 0.5))
                .frame(width: 21, height: 21)
                .background(Circle().fill(.white.opacity(selected ? 0.16 : hover.on ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .hoverAlways { hover.on = $0 }
        .animation(.easeOut(duration: 0.15), value: hover.on)
        .animation(.easeOut(duration: 0.2), value: selected)
        .help(page.title)
    }
}

// MARK: - Curseur de valeur (volume)

struct ValueSlider: View {
    let value: Double
    let enabled: Bool
    let accent: Color
    let onChange: (Double, Bool) -> Void
    @StateObject private var hover = HoverBox()
    @StateObject private var drag = HoverBox()

    var body: some View {
        GeometryReader { g in
            let f = min(max(value, 0), 1)
            let active = (hover.on || drag.on) && enabled
            let h: CGFloat = active ? 7 : 5
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: h)
                Capsule().fill(enabled ? accent : .white.opacity(0.3))
                    .frame(width: max(h, g.size.width * f), height: h)
                Circle().fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: min(max(0, g.size.width * f - 6), g.size.width - 12))
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
                        guard enabled else { return }
                        drag.on = true
                        onChange(min(max(v.location.x / g.size.width, 0), 1), true)
                    }
                    .onEnded { v in
                        guard enabled else { return }
                        drag.on = false
                        onChange(min(max(v.location.x / g.size.width, 0), 1), false)
                    }
            )
            .opacity(enabled ? 1 : 0.5)
        }
    }
}

// MARK: - Presse-papier

struct ClipboardPage: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var ui: NotchUIState
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: ui.geometry.notchHeight + 2)
            HStack {
                Text("Presse-papier")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                if store.items.contains(where: { !$0.pinned }) {
                    Button("Effacer") { store.clearUnpinned() }
                        .buttonStyle(PressStyle())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 26)
            .frame(height: 22)

            if store.items.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 20)).foregroundStyle(.white.opacity(0.35))
                    Text("Copie du texte : il apparaîtra ici.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(store.items) { ClipRow(item: $0, store: store, accent: accent) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                }
            }
        }
    }
}

private struct ClipRow: View {
    let item: ClipItem
    @ObservedObject var store: ClipboardStore
    let accent: Color
    @StateObject private var hover = HoverBox()

    private var preview: String {
        item.text.replacingOccurrences(of: "\n", with: " ⏎ ").replacingOccurrences(of: "\t", with: " ")
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.pinned ? "pin.fill" : "text.alignleft")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.pinned ? accent : .white.opacity(0.4))
                    .frame(width: 14)
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { store.copy(item) }

            if store.copiedID == item.id {
                Text("Copié ✓").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
            } else if hover.on {
                miniButton(item.pinned ? "pin.slash" : "pin") { store.togglePin(item) }
                miniButton("trash") { store.remove(item) }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hover.on ? 0.1 : 0)))
        .hoverAlways { hover.on = $0 }
        .animation(.easeOut(duration: 0.12), value: hover.on)
    }

    private func miniButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Étendoir à captures d'écran

final class ShelfScroll: ObservableObject {
    @Published var first: URL?
}

struct ShelfPage: View {
    @ObservedObject var shelf: ScreenshotShelf
    @ObservedObject var ui: NotchUIState
    let accent: Color
    @StateObject private var scroll = ShelfScroll()

    private let size = NotchPage.shelf.size
    private let thumb = CGSize(width: 90, height: 64)
    private let visibleSlots = 5
    private let sidePad: CGFloat = 22

    private var slotW: CGFloat { (size.width - 2 * sidePad) / CGFloat(visibleSlots) }
    /// Portée d'un brin de corde (une « portée » = l'écran visible).
    private var span: CGFloat { size.width - 16 }

    private func ropeY(_ x: CGFloat, top: CGFloat) -> CGFloat {
        let u = ((x - 8).truncatingRemainder(dividingBy: span)) / span
        return top + 32 * (1 - u) * u
    }

    var body: some View {
        // Le défilement commence sous la zone des onglets, sinon il capte leurs clics.
        let notchH = ui.geometry.notchHeight
        let top: CGFloat = 14
        let scrollH = size.height - notchH
        let n = shelf.shots.count
        let slots = max(n, visibleSlots)
        let segs = max(1, Int(ceil((slotW * CGFloat(slots) + 2 * sidePad - 16) / span)))
        let contentW = 16 + CGFloat(segs) * span
        let firstIndex = shelf.shots.firstIndex { $0.url == scroll.first } ?? 0

        ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: sidePad, height: 1)
                    ForEach(Array(shelf.shots.enumerated()), id: \.element.id) { i, shot in
                        let cx = sidePad + slotW * (CGFloat(i) + 0.5)
                        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !ui.expanded)) { ctx in
                            let t = ctx.date.timeIntervalSinceReferenceDate
                            let tilt = [-2.2, 1.6, -1.0, 2.4, -1.8][i % 5]
                            let sway = sin(t * 1.1 + Double(i) * 1.7) * 1.4
                            HangingShot(shot: shot, shelf: shelf, thumb: thumb)
                                .rotationEffect(.degrees(tilt + sway), anchor: .top)
                        }
                        .frame(width: slotW, height: scrollH - ropeY(cx, top: top), alignment: .top)
                        .padding(.top, ropeY(cx, top: top) - 4)
                        .id(shot.url)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .opacity))
                    }
                    if n < visibleSlots {
                        ForEach(n..<visibleSlots, id: \.self) { i in
                            let cx = sidePad + slotW * (CGFloat(i) + 0.5)
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .frame(width: thumb.width, height: thumb.height)
                                .frame(width: slotW)
                                .padding(.top, ropeY(cx, top: top) + 10)
                        }
                    }
                    Color.clear.frame(width: sidePad, height: 1)
                }
                .scrollTargetLayout()
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: shelf.shots.map(\.url))
                .frame(width: contentW, alignment: .leading)
                .background(alignment: .topLeading) {
                    Path { p in
                        for k in 0..<segs {
                            let x0 = 8 + CGFloat(k) * span
                            p.move(to: CGPoint(x: x0, y: top))
                            p.addQuadCurve(to: CGPoint(x: x0 + span, y: top), control: CGPoint(x: x0 + span / 2, y: top + 16))
                        }
                    }
                    .stroke(Color(red: 0.86, green: 0.74, blue: 0.55), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                }
            }
            .scrollPosition(id: $scroll.first, anchor: .leading)
            .frame(width: size.width, height: scrollH, alignment: .topLeading)
            .offset(y: notchH)

            if firstIndex > 0 {
                chevron("chevron.left") { go(to: firstIndex - 4) }
                    .offset(x: 16, y: notchH + top + 22)
            }
            if firstIndex + visibleSlots < n {
                chevron("chevron.right") { go(to: firstIndex + 4) }
                    .offset(x: size.width - 40, y: notchH + top + 22)
            }

            if shelf.shots.isEmpty {
                Text(shelf.accessDenied
                     ? "Autorise l'accès au dossier des captures (Réglages Système → Confidentialité)."
                     : "Tes dernières captures d'écran s'accrochent ici.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(width: size.width - 60)
                    .offset(x: 30, y: notchH + top + 90)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func go(to index: Int) {
        let i = min(max(0, index), shelf.shots.count - 1)
        withAnimation(.easeInOut(duration: 0.35)) { scroll.first = shelf.shots[i].url }
    }

    private func chevron(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.black.opacity(0.7)))
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
    }
}

private struct HangingShot: View {
    let shot: Shot
    @ObservedObject var shelf: ScreenshotShelf
    let thumb: CGSize
    @StateObject private var hover = HoverBox()

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .top) {
                Image(nsImage: shot.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumb.width, height: thumb.height)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.5), radius: hover.on ? 8 : 4, y: 2)
                    .padding(.top, 7)
                Peg()
            }
            .overlay(alignment: .topTrailing) {
                if hover.on {
                    Button { shelf.dismiss(shot) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressStyle())
                    .offset(x: -4, y: 11)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .help("Retirer de l'étendoir")
                }
            }
            Text(Self.formatter.localizedString(for: shot.date, relativeTo: Date()))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .scaleEffect(hover.on ? 1.1 : 1, anchor: .top)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover.on)
        .hoverAlways { hover.on = $0 }
        .onTapGesture { NSWorkspace.shared.open(shot.url) }
        .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Copier l'image") {
                if let img = NSImage(contentsOf: shot.url) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([img])
                }
            }
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([shot.url]) }
            Button("Retirer de l'étendoir") { shelf.dismiss(shot) }
            Button("Mettre à la corbeille") {
                NSWorkspace.shared.recycle([shot.url]) { _, _ in DispatchQueue.main.async { shelf.dismiss(shot) } }
            }
        }
        .help("Clic : ouvrir · Glisser : déposer ailleurs")
    }
}

/// Pince à linge.
private struct Peg: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
            .frame(width: 7, height: 15)
            .overlay(Rectangle().fill(.black.opacity(0.25)).frame(height: 0.5).offset(y: 3))
            .shadow(color: .black.opacity(0.4), radius: 1.2, y: 1)
    }
}

// MARK: - Audio

struct AudioPage: View {
    @ObservedObject var mixer: AudioMixer
    @ObservedObject var ui: NotchUIState
    let accent: Color

    private var outSymbol: String {
        if mixer.outMuted || mixer.outVolume <= 0.001 { return "speaker.slash.fill" }
        return mixer.outVolume < 0.34 ? "speaker.wave.1.fill" : (mixer.outVolume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
    }

    var body: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: ui.geometry.notchHeight + 2)

            HStack(spacing: 10) {
                Button { mixer.toggleMute() } label: {
                    Image(systemName: outSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(mixer.outMuted ? .white.opacity(0.4) : .white)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                // En sourdine, le niveau reste affiché (grisé) au lieu de tomber à 0 %.
                ValueSlider(value: Double(mixer.outVolume), enabled: mixer.outVolumeAvailable,
                            accent: mixer.outMuted ? .white.opacity(0.4) : accent) { v, dragging in mixer.setOutputVolume(Float(v), dragging: dragging) }
                    .frame(height: 24)
                percent(mixer.outVolumeAvailable ? Int(mixer.outVolume * 100) : nil, dimmed: mixer.outMuted)
            }

            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(mixer.inVolumeAvailable ? 0.9 : 0.4))
                    .frame(width: 24, height: 24)
                ValueSlider(value: Double(mixer.inVolume), enabled: mixer.inVolumeAvailable,
                            accent: accent) { v, dragging in mixer.setInputVolume(Float(v), dragging: dragging) }
                    .frame(height: 24)
                percent(mixer.inVolumeAvailable ? Int(mixer.inVolume * 100) : nil)
            }

            DeviceChips(devices: mixer.outputs, current: mixer.currentOutput, accent: accent,
                        select: mixer.selectOutput)
            DeviceChips(devices: mixer.inputs, current: mixer.currentInput, accent: accent,
                        select: mixer.selectInput)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .onAppear { if ui.expanded { mixer.start() } }
        .onChange(of: ui.expanded) { _, open in open ? mixer.start() : mixer.stop() }
        .onDisappear { mixer.stop() }
    }

    private func percent(_ v: Int?, dimmed: Bool = false) -> some View {
        Text(v.map { "\($0)%" } ?? "—")
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(dimmed ? 0.3 : 0.6))
            .frame(width: 34, alignment: .trailing)
    }
}

private struct DeviceChips: View {
    let devices: [AudioDev]
    let current: AudioDeviceID
    let accent: Color
    let select: (AudioDev) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(devices) { d in
                    let on = d.id == current
                    Button { select(d) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: d.symbol).font(.system(size: 10, weight: .semibold))
                            Text(d.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        }
                        .foregroundStyle(on ? Color.black : .white.opacity(0.8))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(on ? accent : Color.white.opacity(0.12)))
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .frame(height: 26)
        // Fondu sur le bord droit : la liste défile horizontalement.
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88),
                                     .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
    }
}
