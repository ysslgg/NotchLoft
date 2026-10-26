import AppKit
import Combine
import SwiftUI

/// État observable par les vues ; interpole la position de lecture avec un timer.
@MainActor
final class NowPlayingModel: ObservableObject {
    @Published private(set) var hasTrack = false
    /// Faux après une longue pause : l'encoche retourne au repos complet.
    @Published private(set) var isShown = false
    @Published private(set) var sourceIcon: NSImage?
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var position: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published private var extractedAccent: NSColor = AccentColor.fallback
    var accent: Color { Settings.shared.accent.color ?? Color(nsColor: extractedAccent) }

    let service = NowPlayingService()

    private var base: TrackSnapshot?
    private var timer: Timer?
    private var idleWork: DispatchWorkItem?
    private var sourceBundle: String?
    private var pauseArmed = false

    /// Le timer ne tourne que lorsque la position est affichée.
    var tracksPosition = false {
        didSet {
            guard tracksPosition != oldValue else { return }
            stopTimer()
            startTimer()
        }
    }

    private var settingsObserver: AnyCancellable?

    init() {
        settingsObserver = Settings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
        service.onUpdate = { [weak self] snap in
            MainActor.assumeIsolated { self?.apply(snap) }
        }
    }

    func start() {
        startTimer()
        service.start()
    }
    func stop() { service.stop() }

    private func apply(_ snap: TrackSnapshot?) {
        base = snap
        guard let s = snap else {
            hasTrack = false
            isPlaying = false
            updateShown()
            return
        }
        if title != s.title { title = s.title }
        if artist != s.artist { artist = s.artist }
        if isPlaying != s.playing { isPlaying = s.playing }
        if duration != s.duration { duration = s.duration }
        artwork = s.artwork
        extractedAccent = s.accent
        position = computePosition()
        if !hasTrack { hasTrack = true }
        if sourceBundle != s.bundleID {
            sourceBundle = s.bundleID
            sourceIcon = s.bundleID.flatMap { id in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                    .map { NSWorkspace.shared.icon(forFile: $0.path) }
            }
        }
        updateShown()
    }

    /// Masque l'encoche après `idleDelay` secondes de pause, la réaffiche dès que ça rejoue.
    private func updateShown() {
        guard hasTrack else {
            idleWork?.cancel(); idleWork = nil
            pauseArmed = false
            isShown = false
            return
        }
        if isPlaying {
            idleWork?.cancel(); idleWork = nil
            pauseArmed = false
            isShown = true
        } else if !pauseArmed {
            // Premier état « en pause » : visible, puis masqué après le délai.
            pauseArmed = true
            isShown = true
            guard let delay = Settings.shared.idleDelay.seconds else { return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.isShown = false }
            }
            idleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func openSourceApp() {
        guard let id = sourceBundle,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func computePosition() -> Double {
        guard let b = base else { return 0 }
        var t = b.elapsed
        if b.playing { t += Date().timeIntervalSince(b.timestamp) * b.rate }
        return b.duration > 0 ? min(max(0, t), b.duration) : max(0, t)
    }

    private func startTimer() {
        position = computePosition()
        // Rapide quand la position est affichée en grand, lent pour la bague du mode compact.
        let t = Timer(timeInterval: tracksPosition ? 0.1 : 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.base?.playing == true else { return }
                self.position = self.computePosition()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Actions

    func togglePlayPause() {
        service.send(.toggle)
        if var b = base {
            b.elapsed = computePosition(); b.timestamp = Date(); b.playing.toggle()
            base = b; isPlaying = b.playing
        }
    }
    func next() { service.send(.next) }
    func previous() { service.send(.previous) }

    func seek(toFraction f: Double) {
        guard duration > 0 else { return }
        let t = min(max(0, f), 1) * duration
        service.seek(to: t)
        if var b = base { b.elapsed = t; b.timestamp = Date(); base = b }
        position = t
    }
}
