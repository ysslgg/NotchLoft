import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dépôt de fichiers

struct FilesPage: View {
    @ObservedObject var tray: FileTray
    @ObservedObject var ui: NotchUIState
    let accent: Color
    @StateObject private var target = HoverBox()

    private let slotW: CGFloat = 92
    private let sidePad: CGFloat = 22

    private func ropeY(_ x: CGFloat, top: CGFloat, span: CGFloat) -> CGFloat {
        let u = ((x - 8).truncatingRemainder(dividingBy: span)) / span
        return top + 28 * (1 - u) * u
    }

    var body: some View {
        let size = ui.pageSize
        let notchH = ui.geometry.notchHeight
        let areaH = size.height - notchH
        let top: CGFloat = 12
        let span = size.width - 16
        let n = tray.items.count
        let contentW = max(size.width, 2 * sidePad + slotW * CGFloat(n))
        let segs = max(1, Int(ceil((contentW - 16) / span)))

        VStack(spacing: 0) {
            Spacer().frame(height: notchH)
            ZStack(alignment: .topLeading) {
                if n == 0 {
                    emptyState
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 0) {
                            Color.clear.frame(width: sidePad, height: 1)
                            ForEach(Array(tray.items.enumerated()), id: \.element.id) { i, item in
                                let cx = sidePad + slotW * (CGFloat(i) + 0.5)
                                FileCard(item: item, tray: tray)
                                    .rotationEffect(.degrees([-2.0, 1.6, -1.2, 2.2, -1.6][i % 5]), anchor: .top)
                                    .frame(width: slotW, alignment: .top)
                                    .padding(.top, ropeY(cx, top: top, span: span) - 2)
                                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                            removal: .opacity))
                            }
                            Color.clear.frame(width: sidePad, height: 1)
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: tray.items.map(\.id))
                        .frame(width: contentW, alignment: .leading)
                        .background(alignment: .topLeading) {
                            Path { p in
                                for k in 0..<segs {
                                    let x0 = 8 + CGFloat(k) * span
                                    p.move(to: CGPoint(x: x0, y: top))
                                    p.addQuadCurve(to: CGPoint(x: x0 + span, y: top),
                                                   control: CGPoint(x: x0 + span / 2, y: top + 14))
                                }
                            }
                            .stroke(Color(red: 0.86, green: 0.74, blue: 0.55), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                        }
                    }
                    .frame(width: size.width, height: areaH - 24, alignment: .topLeading)

                    HStack {
                        Text("\(n) élément\(n > 1 ? "s" : "") · glisse-les où tu veux")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer()
                        Button("Tout retirer") { tray.clear() }
                            .buttonStyle(PressStyle())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 26)
                    .frame(width: size.width)
                    .offset(y: areaH - 22)
                }
            }
            .frame(width: size.width, height: areaH, alignment: .topLeading)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent.opacity(target.on ? 0.9 : 0), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.opacity(target.on ? 0.12 : 0)))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .animation(.easeOut(duration: 0.15), value: target.on)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .onDrop(of: [UTType.fileURL], isTargeted: Binding(get: { target.on }, set: { target.on = $0 })) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { tray.add([url]) } }
                }
            }
            return true
        }
        .onAppear { if ui.expanded { tray.startWatching() } }
        .onChange(of: ui.expanded) { _, open in open ? tray.startWatching() : tray.stopWatching() }
        .onDisappear { tray.stopWatching() }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(target.on ? 0.9 : 0.4))
            Text("Glisse des fichiers ou des dossiers ici")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Text("Ils restent accrochés jusqu'à ce que tu les reprennes.")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 14)
    }
}

private struct FileCard: View {
    let item: TrayItem
    @ObservedObject var tray: FileTray
    @StateObject private var hover = HoverBox()

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    .overlay(
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                            .resizable()
                            .frame(width: 40, height: 40)
                            .padding(.top, 6)
                    )
                    .frame(width: 66, height: 60)
                    .shadow(color: .black.opacity(0.45), radius: hover.on ? 8 : 4, y: 2)
                    .padding(.top, 7)
                Peg()
            }
            .overlay(alignment: .topTrailing) {
                if hover.on {
                    Button { tray.remove(item) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressStyle())
                    .offset(x: -3, y: 12)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .help("Retirer du dépôt (le fichier reste intact)")
                }
            }
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 82)
        }
        .scaleEffect(hover.on ? 1.08 : 1, anchor: .top)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover.on)
        .hoverAlways { hover.on = $0 }
        .onTapGesture { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Copier le chemin") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            }
            Button("Retirer du dépôt") { tray.remove(item) }
        }
        .help(item.path)
    }
}

// MARK: - Batterie et système

enum SystemMetric: String, CaseIterable, Identifiable {
    case battery, cpu, memory, disk
    var id: String { rawValue }
    var title: String {
        switch self {
        case .battery: "Batterie"
        case .cpu: "Processeur"
        case .memory: "Mémoire"
        case .disk: "Disque"
        }
    }
}

struct SystemPage: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var ui: NotchUIState
    @ObservedObject private var settings = Settings.shared
    let accent: Color

    /// L'info en grand ; la batterie est écartée sur un Mac sans batterie.
    private var hero: SystemMetric {
        let m = SystemMetric(rawValue: settings.systemHero) ?? .battery
        return m == .battery && !monitor.battery.hasBattery ? .cpu : m
    }

    private var others: [SystemMetric] {
        SystemMetric.allCases.filter { $0 != hero && ($0 != .battery || monitor.battery.hasBattery) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: ui.geometry.notchHeight + 2)
            heroView
                .id(hero)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .frame(height: 46)
            HStack(spacing: 0) {
                ForEach(others) { m in
                    // Seule la jauge elle-même est cliquable, pas le vide autour : le geste est posé
                    // avant que la colonne ne s'étire sur toute sa largeur.
                    gauge(m)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { settings.systemHero = m.rawValue } }
                        .help("Afficher « \(m.title) » en grand")
                        .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hero)
        .onChange(of: hero) { _, h in monitor.trackHistory = (h == .cpu) }
        .onAppear { monitor.trackHistory = (hero == .cpu); if ui.expanded { monitor.start() } }
        .onChange(of: ui.expanded) { _, open in open ? monitor.start() : monitor.stop() }
        .onDisappear { monitor.stop() }
    }

    // MARK: Valeurs

    private func fraction(_ m: SystemMetric) -> Double {
        switch m {
        case .battery: return Double(monitor.battery.percent) / 100
        case .cpu: return monitor.cpu
        case .memory: return monitor.memoryUsed
        case .disk: return monitor.diskUsed
        }
    }

    private func detail(_ m: SystemMetric) -> String {
        switch m {
        case .battery: return monitor.battery.isCharging ? "En charge" : (monitor.battery.isPluggedIn ? "Branchée" : "Sur batterie")
        case .cpu: return String(format: "%.0f %%", monitor.cpu * 100)
        case .memory: return String(format: "%.1f / %.0f Go", locale: Locale(identifier: "fr_FR"), monitor.memoryUsedGB, monitor.memoryTotalGB)
        case .disk: return String(format: "%.0f Go libres", monitor.diskFreeGB)
        }
    }

    private func color(_ m: SystemMetric) -> Color {
        if m == .battery { return batteryColor }
        let v = fraction(m)
        return v > 0.9 ? Color(red: 1, green: 0.4, blue: 0.4) : (v > 0.75 ? Color(red: 1, green: 0.7, blue: 0.3) : accent)
    }

    private var batteryColor: Color {
        let b = monitor.battery
        if b.isCharging || b.isPluggedIn { return Color(red: 0.35, green: 0.85, blue: 0.5) }
        return b.percent <= 20 ? Color(red: 1, green: 0.4, blue: 0.4) : .white
    }

    private func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min"
    }

    private var batteryStatus: String {
        let b = monitor.battery
        if b.isFull && b.isPluggedIn { return "Chargée · branchée" }
        if b.isCharging { return "En charge" + (b.minutes.map { " · \(duration($0)) avant 100 %" } ?? "") }
        if b.isPluggedIn { return "Branchée" }
        return "Sur batterie" + (b.minutes.map { " · \(duration($0)) restantes" } ?? "")
    }

    // MARK: Info en grand

    @ViewBuilder private var heroView: some View {
        switch hero {
        case .battery: batteryHero
        case .cpu:
            bigNumber(String(format: "%.0f %%", monitor.cpu * 100), "Processeur · charge", color: color(.cpu)) {
                VStack(alignment: .trailing, spacing: 3) {
                    Sparkline(values: monitor.cpuHistory, color: color(.cpu)).frame(width: 150, height: 28)
                    Text("Pression thermique : \(monitor.thermal)")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
            }
        case .memory:
            bigNumber(String(format: "%.0f %%", monitor.memoryUsed * 100),
                      String(format: "%.1f sur %.0f Go utilisés", locale: Locale(identifier: "fr_FR"), monitor.memoryUsedGB, monitor.memoryTotalGB),
                      color: color(.memory)) { bar(monitor.memoryUsed, color(.memory)) }
        case .disk:
            bigNumber(String(format: "%.0f Go", monitor.diskFreeGB),
                      String(format: "libres sur %.0f Go · %.0f %% utilisé", monitor.diskTotalGB, monitor.diskUsed * 100),
                      color: color(.disk)) { bar(monitor.diskUsed, color(.disk)) }
        }
    }

    private func bar(_ value: Double, _ c: Color) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.15))
            Capsule().fill(c).frame(width: 150 * max(0.02, min(1, value)))
        }
        .frame(width: 150, height: 8)
        .animation(.easeOut(duration: 0.5), value: value)
    }

    private func bigNumber<T: View>(_ value: String, _ caption: String, color: Color,
                                    @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            trailing()
        }
    }

    @ViewBuilder private var batteryHero: some View {
        let b = monitor.battery
        HStack(spacing: 12) {
            BatteryGlyph(percent: b.percent, charging: b.isCharging || b.isPluggedIn, color: batteryColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(b.percent) %")
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(batteryStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                if let h = b.health {
                    Label("Santé \(h) %", systemImage: "heart.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                if let c = b.cycles {
                    Text("\(c) cycles")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    // MARK: Jauges (cliquables)

    private func gauge(_ m: SystemMetric) -> some View {
        let value = fraction(m)
        return VStack(spacing: 5) {
            ZStack {
                Circle().stroke(.white.opacity(0.14), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.01, min(1, value)))
                    .stroke(color(m), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: value)
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            VStack(spacing: 0) {
                Text(m.title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                Text(detail(m)).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
        }
        .fixedSize()
    }
}

private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { g in
            // La mesure la plus récente est à droite ; la courbe défile vers la gauche.
            let step = g.size.width / 39
            let pts = values.enumerated().map { i, v in
                CGPoint(x: g.size.width - CGFloat(values.count - 1 - i) * step,
                        y: g.size.height * (1 - CGFloat(min(1, max(0, v)))))
            }
            ZStack {
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: CGPoint(x: f.x, y: g.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
        }
    }
}

private struct BatteryGlyph: View {
    let percent: Int
    let charging: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(color)
                    .frame(width: max(5, 42 * CGFloat(min(100, max(0, percent))) / 100), height: 17)
                    .padding(.leading, 3)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))
                        .frame(width: 48)
                }
            }
            .frame(width: 48, height: 24)
            Capsule().fill(.white.opacity(0.55)).frame(width: 3, height: 9)
        }
    }
}
