import AppKit
import Foundation

/// État de lecture tel que décrit par l'adaptateur MediaRemote.
struct TrackSnapshot {
    var title: String
    var artist: String
    var album: String
    var playing: Bool
    var duration: Double
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var artwork: NSImage?
    var accent: NSColor
    var bundleID: String?
}

/// Lance `perl mediaremote-adapter.pl <framework> stream` et expose les mises à jour.
final class NowPlayingService: @unchecked Sendable {
    var onUpdate: ((TrackSnapshot?) -> Void)?

    private let io = DispatchQueue(label: "notchloft.nowplaying")
    private var process: Process?
    private var buffer = Data()
    private var payload: [String: Any] = [:]
    private var stopping = false

    private var artworkKey: Int?
    private var artwork: NSImage?
    private var accent: NSColor = AccentColor.fallback

    // MARK: Chemins

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    private static func locate() -> (script: URL, framework: URL)? {
        let fm = FileManager.default
        var candidates: [(URL, URL)] = []
        if let res = Bundle.main.resourceURL, let fw = Bundle.main.privateFrameworksURL {
            candidates.append((res.appendingPathComponent("mediaremote-adapter.pl"),
                               fw.appendingPathComponent("MediaRemoteAdapter.framework")))
        }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        candidates.append((cwd.appendingPathComponent(".build-adapter/src/bin/mediaremote-adapter.pl"),
                           cwd.appendingPathComponent(".build-adapter/src/build/MediaRemoteAdapter.framework")))
        return candidates.first { fm.fileExists(atPath: $0.0.path) && fm.fileExists(atPath: $0.1.path) }
    }

    // MARK: Cycle de vie

    func start() {
        io.async {
            Self.killStrayAdapters()
            self.launch()
        }
    }

    /// Un adaptateur resté en vie après un arrêt brutal de l'app (parent = launchd) est supprimé.
    private static func killStrayAdapters() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,ppid=,command="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where line.contains("mediaremote-adapter.pl") {
            let f = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            if f.count == 3, f[1] == "1", let pid = pid_t(f[0]) { kill(pid, SIGTERM) }
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
    }

    private func launch() {
        guard let paths = Self.locate() else {
            NSLog("NotchLoft: adaptateur MediaRemote introuvable")
            return
        }
        let p = Process()
        p.executableURL = Self.perl
        p.arguments = [paths.script.path, paths.framework.path, "stream", "--micros", "--debounce=40"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.io.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in
            guard let self, !self.stopping else { return }
            self.io.asyncAfter(deadline: .now() + 2) { self.launch() }
        }
        buffer = Data()
        payload = [:]
        do {
            try p.run()
            process = p
        } catch {
            NSLog("NotchLoft: impossible de lancer perl: \(error)")
        }
    }

    // MARK: Lecture du flux

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<nl])
            buffer.removeSubrange(buffer.startIndex...nl)
            if !line.isEmpty { handle(line) }
        }
    }

    private func handle(_ line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "data",
              let incoming = obj["payload"] as? [String: Any] else { return }
        let isDiff = obj["diff"] as? Bool ?? false
        if isDiff {
            for (key, value) in incoming {
                if value is NSNull { payload.removeValue(forKey: key) } else { payload[key] = value }
            }
        } else {
            payload = incoming.filter { !($0.value is NSNull) }
        }
        publish()
    }

    private func publish() {
        guard let title = payload["title"] as? String, !title.isEmpty else {
            DispatchQueue.main.async { self.onUpdate?(nil) }
            return
        }
        updateArtwork()
        let micros: (String) -> Double? = { (self.payload[$0] as? NSNumber)?.doubleValue }
        let playing = payload["playing"] as? Bool ?? false
        let rate = (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        let ts = micros("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? Date()
        let snap = TrackSnapshot(
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            playing: playing,
            duration: (micros("durationMicros") ?? 0) / 1_000_000,
            elapsed: (micros("elapsedTimeMicros") ?? 0) / 1_000_000,
            timestamp: ts,
            rate: rate > 0 ? rate : 1,
            artwork: artwork,
            accent: accent,
            bundleID: payload["bundleIdentifier"] as? String
        )
        DispatchQueue.main.async { self.onUpdate?(snap) }
    }

    private func updateArtwork() {
        guard let b64 = payload["artworkData"] as? String else {
            artworkKey = nil; artwork = nil; accent = AccentColor.fallback
            return
        }
        let key = b64.hashValue
        guard key != artworkKey else { return }
        artworkKey = key
        if let data = Data(base64Encoded: b64), let image = NSImage(data: data) {
            artwork = image
            accent = AccentColor.extract(from: image)
        } else {
            artwork = nil; accent = AccentColor.fallback
        }
    }

    // MARK: Commandes

    enum Command: Int { case play = 0, pause = 1, toggle = 2, next = 4, previous = 5 }

    func send(_ command: Command) { run(["send", String(command.rawValue)]) }

    func seek(to seconds: Double) { run(["seek", String(Int64(max(0, seconds) * 1_000_000))]) }

    private func run(_ args: [String]) {
        guard let paths = Self.locate() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = Self.perl
            p.arguments = [paths.script.path, paths.framework.path] + args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }
}
