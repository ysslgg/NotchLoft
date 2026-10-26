import AppKit
import SwiftUI

// MARK: - Onglets (dans les « ailes » de part et d'autre de l'encoche physique)

struct PageTabs: View {
    @ObservedObject var ui: NotchUIState
    let accent: Color

    var body: some View {
        let pages = NotchPage.enabled
        if pages.count > 1 {
            let half = (pages.count + 1) / 2
            // Boutons alignés sur les marges du contenu : à gauche pour les premiers, à droite pour les derniers.
            HStack(spacing: 0) {
                HStack(spacing: 2) { ForEach(Array(pages.prefix(half))) { tab($0) } }
                    .fixedSize()
                Spacer(minLength: ui.geometry.notchWidth)
                HStack(spacing: 2) { ForEach(Array(pages.dropFirst(half))) { tab($0) } }
                    .fixedSize()
            }
            .padding(.horizontal, 28)
            .frame(height: ui.geometry.notchHeight)
        }
    }

    private func tab(_ page: NotchPage) -> some View {
        TabButton(page: page, selected: ui.effectivePage == page, accent: accent) { ui.select(page) }
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

// MARK: - Presse-papier

struct ClipboardPage: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var ui: NotchUIState
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: ui.geometry.notchHeight + 2)
            HStack {
                Text(tr("Clipboard"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                if store.items.contains(where: { !$0.pinned }) {
                    Button(tr("Clear")) { store.clearUnpinned() }
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
                    Text(tr("Copy some text and it will show up here."))
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
                Text(tr("Copied ✓")).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
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
                        HangingShot(shot: shot, shelf: shelf, thumb: thumb, index: i)
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
                     ? tr("Allow access to the screenshots folder (System Settings → Privacy & Security).")
                     : tr("Your latest screenshots hang here."))
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
    let index: Int
    @StateObject private var hover = HoverBox()

    private var tilt: Double { [-2.2, 1.6, -1.0, 2.4, -1.8][index % 5] }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: Settings.shared.language.rawValue)
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private static func clock(_ t: Double) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

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
                    .overlay(alignment: .bottomLeading) {
                        if shot.isVideo {
                            HStack(spacing: 3) {
                                Image(systemName: "play.fill").font(.system(size: 7, weight: .bold))
                                Text(Self.clock(shot.duration)).font(.system(size: 9, weight: .semibold).monospacedDigit())
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(height: 15)
                            .background(Capsule().fill(Color.black.opacity(0.7)))
                            .padding(5)
                        }
                    }
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
                    .help(tr("Remove from shelf"))
                }
            }
            Text(Self.relative(shot.date))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .scaleEffect(hover.on ? 1.1 : 1, anchor: .top)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover.on)
        // Au survol, la capture se redresse en pendulant une fois (aucune animation permanente).
        .rotationEffect(.degrees(hover.on ? 0 : tilt), anchor: .top)
        .animation(.interpolatingSpring(stiffness: 90, damping: 5), value: hover.on)
        .hoverAlways { hover.on = $0 }
        .onTapGesture { NSWorkspace.shared.open(shot.url) }
        .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
        .contextMenu {
            Button(tr("Copy image")) {
                if let img = NSImage(contentsOf: shot.url) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([img])
                    shelf.ignoreCurrentPasteboard()
                }
            }
            Button(tr("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([shot.url]) }
            Button(tr("Remove from shelf")) { shelf.dismiss(shot) }
            Button(tr("Move to Trash")) {
                NSWorkspace.shared.recycle([shot.url]) { _, _ in DispatchQueue.main.async { shelf.dismiss(shot) } }
            }
        }
        .help(tr("Click: open · Drag: drop elsewhere"))
    }
}

/// Pince à linge.
struct Peg: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
            .frame(width: 7, height: 15)
            .overlay(Rectangle().fill(.black.opacity(0.25)).frame(height: 0.5).offset(y: 3))
            .shadow(color: .black.opacity(0.4), radius: 1.2, y: 1)
    }
}
