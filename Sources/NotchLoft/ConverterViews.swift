import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Retour à la ligne automatique pour les pastilles de format.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(width: bounds.width, subviews: subviews)
        for (i, f) in r.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        var frames: [CGRect] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowH), frames)
    }
}

final class HoverTarget: ObservableObject {
    @Published var target: ConvTarget?
}

struct ConverterPage: View {
    @ObservedObject var model: ConverterModel
    @ObservedObject var ui: NotchUIState
    let accent: Color
    @StateObject private var dropping = HoverBox()
    @StateObject private var hovered = HoverTarget()

    var body: some View {
        let size = ui.pageSize
        VStack(spacing: 0) {
            Spacer().frame(height: ui.geometry.notchHeight + 4)
            Group {
                switch model.phase {
                case .idle: idle
                case .loading: centered { ProgressView().controlSize(.small).tint(.white) }
                case .ready, .failed: chooser
                case .running: running
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(dropping.on ? 0.9 : 0), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(accent.opacity(dropping.on ? 0.12 : 0)))
                .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, ui.geometry.notchHeight + 2)
                .animation(.easeOut(duration: 0.15), value: dropping.on)
                .allowsHitTesting(false)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: Binding(get: { dropping.on }, set: { dropping.on = $0 })) { providers in
            loadFileURLs(from: providers) { model.load($0) }
            return true
        }
    }

    // MARK: États

    private func centered<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack { content() }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idle: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(dropping.on ? 0.95 : 0.45))
            Text(tr("Drop files here to convert them"))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
            Text(tr("Images, video, audio, documents, PDF, data, archives…"))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42))
            Button(tr("Choose files…")) { model.browse() }
                .buttonStyle(PressStyle())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 2)
            if !FFmpegConv.available {
                Text(tr("More formats with ffmpeg: brew install ffmpeg"))
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.32)).padding(.top, 2)
            }
        }
        .padding(.bottom, 14)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: model.files[0].path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.files.count == 1 ? model.files[0].lastPathComponent
                                            : tr("%d files", model.files.count))
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { model.reset() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 20, height: 20).background(Circle().fill(.white.opacity(0.12)))
            }
            .buttonStyle(PressStyle())
            .help(tr("Start over"))
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 6)
    }

    private var subtitle: String {
        let total = model.files.reduce(Int64(0)) { sum, u in
            sum + Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let isDir = model.files.count == 1 && ConvDetect.category(model.files[0]) == .folder
        let size = isDir ? "" : " · " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        if model.files.count == 1 { return tr(ConvDetect.typeName(model.files[0])) + size }
        let kinds = Set(model.files.map { ConvDetect.typeName($0) })
        return (kinds.count == 1 ? kinds.first! : tr("Mixed files")) + size
    }

    private var chooser: some View {
        VStack(spacing: 0) {
            header
            if model.phase == .failed {
                Text(model.errorText)
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                    .lineLimit(2).padding(.horizontal, 26).padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.targets.isEmpty {
                centered {
                    Text(tr("No conversion available for this file."))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.groups, id: \.name) { g in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tr(g.name).uppercased())
                                    .font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(.white.opacity(0.38))
                                FlowLayout(spacing: 5) {
                                    ForEach(g.items) { t in
                                        FormatChip(target: t, accent: accent, hovered: hovered) { model.start(t) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 6)
                }
                // Les lignes qui défilent s'effacent en haut et en bas au lieu d'être coupées net
                // (sinon un titre de groupe à moitié visible se superpose à l'en-tête ou à la description).
                .clipped()
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 10)
                        Rectangle().fill(.black)
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 14)
                    }
                )
                // Description du format survolé (zone fixe pour que la page ne saute pas).
                VStack(alignment: .leading, spacing: 1) {
                    if let t = hovered.target {
                        Text(tr(t.label) + (t.ext.isEmpty ? "" : "  ·  .\(t.ext)"))
                            .font(.system(size: 10.5, weight: .bold)).foregroundStyle(accent)
                        Text(tr(ConvBlurb.text(for: t)))
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                    } else {
                        Text(tr("Hover a format to see what it is."))
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .topLeading)
                .padding(.horizontal, 26).padding(.top, 4).padding(.bottom, 10)
            }
        }
    }

    private var running: some View {
        VStack(spacing: 10) {
            Text(tr("Converting to %@…", tr(model.runningLabel)))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            if model.progress > 0.001 && model.progress < 0.999 {
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(accent).frame(width: 260 * model.progress)
                }
                .frame(width: 260, height: 6)
            } else {
                ProgressView().controlSize(.small).tint(.white)
            }
            Button(tr("Cancel")) { model.cancel() }
                .buttonStyle(PressStyle())
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.bottom, 16)
    }

    private var done: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(accent)
            Text(model.outputs.count > 1 ? tr("%d files created", model.outputs.count) : tr("Converted"))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            if let first = model.outputs.first {
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: first.path)).resizable().frame(width: 18, height: 18)
                    Text(first.lastPathComponent).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.09)))
                .onDrag { NSItemProvider(contentsOf: first) ?? NSItemProvider() }
                .help(tr("Drag it anywhere"))
            }
            HStack(spacing: 8) {
                pill(tr("Show in Finder"), filled: true) {
                    NSWorkspace.shared.activateFileViewerSelecting(model.outputs)
                }
                if model.outputs.count == 1 { pill(tr("Open"), filled: false) { NSWorkspace.shared.open(model.outputs[0]) } }
                pill(tr("Convert again"), filled: false) { model.again() }
            }
        }
        .padding(.bottom, 12)
    }

    private func pill(_ title: String, filled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? Color.black : .white.opacity(0.85))
                .padding(.horizontal, 11).frame(height: 24)
                .background(Capsule().fill(filled ? accent : .white.opacity(0.13)))
        }
        .buttonStyle(PressStyle())
    }
}

private struct FormatChip: View {
    let target: ConvTarget
    let accent: Color
    @ObservedObject var hovered: HoverTarget
    let action: () -> Void
    @StateObject private var hover = HoverBox()

    var body: some View {
        Button(action: action) {
            Text(tr(target.label))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hover.on ? Color.black : .white.opacity(0.9))
                .padding(.horizontal, 10).frame(height: 24)
                .background(Capsule().fill(hover.on ? accent : .white.opacity(0.12)))
        }
        .buttonStyle(PressStyle())
        .hoverAlways { on in
            hover.on = on
            if on { hovered.target = target } else if hovered.target == target { hovered.target = nil }
        }
        .animation(.easeOut(duration: 0.1), value: hover.on)
    }
}

// MARK: - Choix lors d'un glissement : étendoir de fichiers ou convertisseur

struct DropChooser: View {
    @ObservedObject var tray: FileTray
    @ObservedObject var converter: ConverterModel
    @ObservedObject var ui: NotchUIState
    let accent: Color
    @StateObject private var overTray = HoverBox()
    @StateObject private var overConvert = HoverBox()

    var body: some View {
        let size = ui.pageSize
        HStack(spacing: 12) {
            zone(symbol: "tray.and.arrow.down", title: tr("Hang in tray"), subtitle: tr("keep it for later"), targeted: overTray.on)
                .onDrop(of: [UTType.fileURL], isTargeted: Binding(get: { overTray.on }, set: { overTray.on = $0 })) { providers in
                    loadFileURLs(from: providers) { tray.add($0) }
                    ui.fileDragActive = false
                    ui.select(.files)
                    return true
                }
            zone(symbol: "arrow.triangle.2.circlepath", title: tr("Convert"), subtitle: tr("pick a new format"), targeted: overConvert.on)
                .onDrop(of: [UTType.fileURL], isTargeted: Binding(get: { overConvert.on }, set: { overConvert.on = $0 })) { providers in
                    loadFileURLs(from: providers) { converter.load($0) }
                    ui.fileDragActive = false
                    ui.select(.convert)
                    return true
                }
        }
        .padding(.horizontal, 20)
        .padding(.top, ui.geometry.notchHeight + 6)
        .padding(.bottom, 16)
        .frame(width: size.width, height: size.height)
        .background(Color.black.opacity(0.001))
    }

    private func zone(symbol: String, title: String, subtitle: String, targeted: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light))
                .foregroundStyle(targeted ? Color.black : .white.opacity(0.7))
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(targeted ? Color.black : .white.opacity(0.9))
            Text(subtitle).font(.system(size: 10.5)).foregroundStyle(targeted ? Color.black.opacity(0.6) : .white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(targeted ? accent : Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(.white.opacity(targeted ? 0 : 0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .animation(.easeOut(duration: 0.12), value: targeted)
    }
}
