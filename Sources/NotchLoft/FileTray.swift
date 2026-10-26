import AppKit

struct TrayItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var path: String
    var added = Date()
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { FileManager.default.displayName(atPath: path) }
}

/// Fichiers et dossiers « accrochés » à l'encoche : de simples références, rien n'est copié ni déplacé.
final class FileTray: ObservableObject {
    @Published private(set) var items: [TrayItem] = []

    static let capacity = 30
    private let fileURL: URL
    private var timer: Timer?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchLoft", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tray.json")
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([TrayItem].self, from: data) {
            items = saved.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    /// Retire les éléments dont le fichier a disparu, tant que la page est ouverte.
    func startWatching() {
        stopWatching()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.prune() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    private func prune() {
        let kept = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        if kept.count != items.count { items = kept; save() }
    }

    func add(_ urls: [URL]) {
        var list = items
        for url in urls where url.isFileURL {
            list.removeAll { $0.path == url.path }
            list.insert(TrayItem(path: url.path), at: 0)
        }
        items = Array(list.prefix(Self.capacity))
        save()
    }

    func remove(_ item: TrayItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        if items.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        } else if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
