import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// État de la page « Convertisseur » : fichiers déposés, formats proposés, conversion en cours, résultat.
@MainActor
final class ConverterModel: ObservableObject {
    enum Phase { case idle, loading, ready, running, done, failed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var files: [URL] = []
    @Published private(set) var targets: [ConvTarget] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var runningLabel = ""
    @Published private(set) var outputs: [URL] = []
    @Published private(set) var errorText = ""

    private var task: Task<Void, Never>?

    init() {
        // Aide aux tests : NOTCHLOFT_CONVERT_TEST=/chemin/a:/chemin/b charge ces fichiers au lancement.
        if let paths = ProcessInfo.processInfo.environment["NOTCHLOFT_CONVERT_TEST"] {
            let urls = paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
            DispatchQueue.main.async { [weak self] in self?.load(urls) }
        }
    }

    static let groupOrder = ["Images", "Video", "Audio", "Documents", "Text", "Data", "Archives"]

    var groups: [(name: String, items: [ConvTarget])] {
        var dict: [String: [ConvTarget]] = [:]
        for t in targets { dict[t.group, default: []].append(t) }
        let known = Self.groupOrder.filter { dict[$0] != nil }
        let extra = dict.keys.filter { !Self.groupOrder.contains($0) }.sorted()
        return (known + extra).map { ($0, dict[$0]!) }
    }

    func load(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        task?.cancel()
        files = existing
        targets = []
        phase = .loading
        Task {
            let found = await Task.detached(priority: .userInitiated) { ConvEngine.targets(for: existing) }.value
            guard self.files == existing else { return }
            self.targets = found
            self.phase = .ready
        }
    }

    func start(_ target: ConvTarget) {
        guard phase == .ready || phase == .failed else { return }
        let urls = files
        runningLabel = target.label
        progress = 0
        phase = .running
        task = Task {
            do {
                let made = try await ConvEngine.convert(urls, with: target, progress: { [weak self] p in
                    Task { @MainActor in self?.progress = p }
                })
                try Task.checkCancellation()
                self.outputs = made
                self.phase = .done
            } catch is CancellationError {
                self.phase = .ready
            } catch ConvError.cancelled {
                self.phase = .ready
            } catch {
                self.errorText = Self.describe(error)
                self.phase = .failed
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .running { phase = .ready }
    }

    /// Revient au choix du format (même fichiers).
    func again() {
        outputs = []
        phase = files.isEmpty ? .idle : .ready
    }

    func reset() {
        task?.cancel()
        files = []; targets = []; outputs = []
        phase = .idle
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case ConvError.unsupported: return tr("This conversion isn't supported")
        case ConvError.toolMissing(let t): return tr("Missing tool: %@", t)
        case ConvError.failed(let m): return tr(m)
        default: return error.localizedDescription
        }
    }

    // MARK: Ouverture de fichiers

    func browse() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { load(panel.urls) }
    }
}

/// Lit les fichiers d'un glisser-déposer.
func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for p in providers {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url, url.isFileURL { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(urls.sorted { $0.path < $1.path }) }
}
