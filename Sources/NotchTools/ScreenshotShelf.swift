import AppKit
import ImageIO

struct Shot: Identifiable, Equatable {
    let url: URL
    let date: Date
    let image: NSImage
    var id: URL { url }
    static func == (a: Shot, b: Shot) -> Bool { a.url == b.url }
}

/// Surveille le dossier des captures d'écran et garde les 5 plus récentes.
final class ScreenshotShelf: ObservableObject {
    @Published private(set) var shots: [Shot] = []
    @Published private(set) var accessDenied = false

    static let capacity = 5

    private var timer: Timer?
    private var dismissed = Set<URL>()
    private var thumbs: [URL: NSImage] = [:]
    private let queue = DispatchQueue(label: "notchtools.shelf", qos: .utility)

    private static let prefixes = ["screenshot", "screen shot", "capture d", "bildschirmfoto", "captura de pantalla",
                                   "schermata", "cleanshot", "capture écran"]
    private static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]

    static func directory() -> URL {
        if let o = ProcessInfo.processInfo.environment["NOTCHTOOLS_SHELF_DIR"], !o.isEmpty {
            return URL(fileURLWithPath: o)
        }
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (loc as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func setEnabled(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        scan()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func dismiss(_ shot: Shot) {
        dismissed.insert(shot.url)
        shots.removeAll { $0 == shot }
        scan()
    }

    private func scan() {
        let dir = Self.directory()
        let hidden = dismissed
        queue.async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let files: [URL]
            do {
                files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey],
                                                   options: [.skipsHiddenFiles])
            } catch {
                DispatchQueue.main.async { self.accessDenied = true }
                return
            }
            let candidates: [(URL, Date)] = files.compactMap { url in
                guard Self.extensions.contains(url.pathExtension.lowercased()) else { return nil }
                let name = url.lastPathComponent.lowercased()
                guard Self.prefixes.contains(where: { name.hasPrefix($0) }), !hidden.contains(url) else { return nil }
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return (url, date)
            }
            let latest = candidates.sorted { $0.1 > $1.1 }.prefix(Self.capacity)
            let result: [Shot] = latest.compactMap { url, date in
                guard let img = self.thumbnail(for: url) else { return nil }
                return Shot(url: url, date: date, image: img)
            }
            DispatchQueue.main.async {
                self.accessDenied = false
                if self.shots.map(\.url) != result.map(\.url) { self.shots = result }
            }
        }
    }

    private func thumbnail(for url: URL) -> NSImage? {
        if let cached = thumbs[url] { return cached }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbs[url] = img
        if thumbs.count > 20 { thumbs = thumbs.filter { $0.key == url } }
        return img
    }
}
