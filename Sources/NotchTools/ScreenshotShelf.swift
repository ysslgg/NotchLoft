import AppKit
import AVFoundation
import ImageIO

struct Shot: Identifiable, Equatable {
    let url: URL
    let date: Date
    let image: NSImage
    let isVideo: Bool
    let duration: Double
    var id: URL { url }
    static func == (a: Shot, b: Shot) -> Bool { a.url == b.url }
}

/// Surveille le dossier des captures (images et enregistrements d'écran) ainsi que les captures
/// copiées dans le presse-papiers, et garde les plus récentes.
final class ScreenshotShelf: ObservableObject {
    @Published private(set) var shots: [Shot] = []
    @Published private(set) var accessDenied = false

    static let capacity = 30

    /// Appelé quand une nouvelle capture arrive : elle reste retenue jusqu'à `release`.
    var arrivalHandler: ((Shot) -> Void)?

    private struct Thumb { let image: NSImage; let isVideo: Bool; let duration: Double }

    private var timer: Timer?
    private var pasteTimer: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedPath: String?
    private var pendingScan: DispatchWorkItem?
    private var dismissed = Set<URL>()
    private var known = Set<URL>()
    private var held = Set<URL>()
    private var latest: [Shot] = []
    private var firstScanDone = false
    private var thumbs: [URL: Thumb] = [:]
    private var lastPasteCount = NSPasteboard.general.changeCount
    private var ignoredPasteCount = -1
    private let queue = DispatchQueue(label: "notchtools.shelf", qos: .utility)

    private static let prefixes = [
        "screenshot", "screen shot", "capture d", "bildschirmfoto", "captura de pantalla", "schermata", "cleanshot",
        "screen recording", "enregistrement de l", "bildschirmaufnahme", "grabación de pantalla",
        "registrazione schermo",
    ]
    private static let imageOnlyTypes: Set<String> = [
        "public.png", "public.tiff", "public.jpeg", "Apple PNG pasteboard type", "NeXT TIFF v4.0 pasteboard type",
    ]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]
    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    static func directory() -> URL {
        if let o = ProcessInfo.processInfo.environment["NOTCHTOOLS_SHELF_DIR"], !o.isEmpty {
            return URL(fileURLWithPath: o)
        }
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (loc as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// Captures copiées dans le presse-papiers (sans fichier) : on les enregistre ici pour pouvoir les accrocher.
    static let captureDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchTools/Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: Surveillance

    func setEnabled(_ on: Bool) {
        timer?.invalidate(); timer = nil
        pasteTimer?.invalidate(); pasteTimer = nil
        watcher?.cancel(); watcher = nil
        watchedPath = nil
        guard on else { return }
        watch(Self.directory())
        scan()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            self?.watch(Self.directory())
            self?.scan()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        lastPasteCount = NSPasteboard.general.changeCount
        let p = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.pollPasteboard() }
        RunLoop.main.add(p, forMode: .common)
        pasteTimer = p
    }

    /// Réagit tout de suite aux changements du dossier plutôt que d'attendre le prochain tour.
    private func watch(_ dir: URL) {
        guard dir.path != watchedPath else { return }
        watcher?.cancel(); watcher = nil
        watchedPath = dir.path
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend],
                                                            queue: .main)
        src.setEventHandler { [weak self] in self?.scanSoon() }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    private func scanSoon() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Une capture copiée dans le presse-papiers (⌃⇧⌘3/4) ne contient que du PNG/TIFF, sans HTML ni URL.
    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastPasteCount else { return }
        lastPasteCount = pb.changeCount
        guard lastPasteCount != ignoredPasteCount else { return }
        let types = Set((pb.types ?? []).map(\.rawValue))
        guard !types.isEmpty, types.isSubset(of: Self.imageOnlyTypes),
              let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: data), rep.pixelsWide >= 200, rep.pixelsHigh >= 120,
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy-MM-dd 'à' HH.mm.ss"
        let url = Self.captureDirectory.appendingPathComponent("Capture presse-papier \(f.string(from: Date())).png")
        try? png.write(to: url)
        scan()
    }

    /// À appeler après une copie d'image faite par l'app elle-même.
    func ignoreCurrentPasteboard() {
        ignoredPasteCount = NSPasteboard.general.changeCount
    }

    // MARK: Liste

    func dismiss(_ shot: Shot) {
        dismissed.insert(shot.url)
        latest.removeAll { $0 == shot }
        publish()
        scan()
    }

    func release(_ url: URL) {
        guard held.remove(url) != nil else { return }
        publish()
    }

    private func publish() {
        let visible = latest.filter { !held.contains($0.url) }
        if shots.map(\.url) != visible.map(\.url) { shots = visible }
    }

    func scan() {
        let dir = Self.directory()
        let hidden = dismissed
        queue.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            var denied = false
            var files: [URL] = []
            do {
                files += try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey],
                                                    options: [.skipsHiddenFiles])
            } catch {
                denied = true
            }
            let ownFiles = (try? fm.contentsOfDirectory(at: Self.captureDirectory, includingPropertiesForKeys: [.creationDateKey],
                                                        options: [.skipsHiddenFiles])) ?? []
            Self.prune(ownFiles)

            let all = files.filter { url in
                let name = url.lastPathComponent.lowercased()
                return Self.prefixes.contains { name.hasPrefix($0) }
            } + ownFiles
            let supported = Self.imageExtensions.union(Self.videoExtensions)
            let candidates: [(URL, Date)] = all.compactMap { url in
                guard supported.contains(url.pathExtension.lowercased()), !hidden.contains(url) else { return nil }
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return (url, date)
            }
            let latest = candidates.sorted { $0.1 > $1.1 }.prefix(Self.capacity)
            let result: [Shot] = latest.compactMap { url, date in
                guard let t = self.thumbnail(for: url) else { return nil }
                return Shot(url: url, date: date, image: t.image, isVideo: t.isVideo, duration: t.duration)
            }
            DispatchQueue.main.async { self.ingest(result, denied: denied && ownFiles.isEmpty) }
        }
    }

    private func ingest(_ result: [Shot], denied: Bool) {
        accessDenied = denied && result.isEmpty
        // « Nouveau » = jamais vu et très récent (un fichier plus ancien qui remonte dans le top n'en est pas un).
        let fresh = firstScanDone
            ? result.filter { !known.contains($0.url) && -$0.date.timeIntervalSinceNow < 30 }
            : []
        known.formUnion(result.map(\.url))
        firstScanDone = true
        latest = result
        if Settings.shared.animateArrivals, let handler = arrivalHandler, let newest = fresh.max(by: { $0.date < $1.date }) {
            held.insert(newest.url)
            publish()
            handler(newest)
            // Filet de sécurité : la capture finit toujours par apparaître.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.release(newest.url) }
        } else {
            publish()
        }
    }

    // MARK: Vignettes

    private func thumbnail(for url: URL) -> Thumb? {
        if let cached = thumbs[url] { return cached }
        let t: Thumb?
        if Self.videoExtensions.contains(url.pathExtension.lowercased()) {
            t = videoThumbnail(url)
        } else {
            t = imageThumbnail(url)
        }
        if let t {
            thumbs[url] = t
            if thumbs.count > 80 { thumbs = thumbs.filter { $0.key == url } }
        }
        return t
    }

    private func imageThumbnail(_ url: URL) -> Thumb? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return Thumb(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), isVideo: false, duration: 0)
    }

    private func videoThumbnail(_ url: URL) -> Thumb? {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else { return nil }   // enregistrement pas encore terminé
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 360, height: 360)
        let at = CMTime(seconds: min(0.4, seconds / 2), preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: at, actualTime: nil) else { return nil }
        return Thumb(image: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), isVideo: true, duration: seconds)
    }

    /// Garde seulement les captures de presse-papiers les plus récentes sur le disque.
    private static func prune(_ files: [URL]) {
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
        for (url, _) in dated.dropFirst(capacity) { try? FileManager.default.removeItem(at: url) }
    }
}
