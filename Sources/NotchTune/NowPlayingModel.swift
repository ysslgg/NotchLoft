import AppKit
import SwiftUI

/// État observable par les vues ; interpole la position de lecture avec un timer.
@MainActor
final class NowPlayingModel: ObservableObject {
    @Published private(set) var hasTrack = false
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var position: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = Color(nsColor: AccentColor.fallback)

    let service = NowPlayingService()

    private var base: TrackSnapshot?
    private var timer: Timer?

    /// Le timer ne tourne que lorsque la position est affichée.
    var tracksPosition = false {
        didSet {
            guard tracksPosition != oldValue else { return }
            tracksPosition ? startTimer() : stopTimer()
        }
    }

    init() {
        service.onUpdate = { [weak self] snap in
            MainActor.assumeIsolated { self?.apply(snap) }
        }
    }

    func start() { service.start() }
    func stop() { service.stop() }

    private func apply(_ snap: TrackSnapshot?) {
        base = snap
        guard let s = snap else {
            hasTrack = false
            isPlaying = false
            return
        }
        if title != s.title { title = s.title }
        if artist != s.artist { artist = s.artist }
        if isPlaying != s.playing { isPlaying = s.playing }
        if duration != s.duration { duration = s.duration }
        artwork = s.artwork
        accent = Color(nsColor: s.accent)
        position = computePosition()
        if !hasTrack { hasTrack = true }
    }

    private func computePosition() -> Double {
        guard let b = base else { return 0 }
        var t = b.elapsed
        if b.playing { t += Date().timeIntervalSince(b.timestamp) * b.rate }
        return b.duration > 0 ? min(max(0, t), b.duration) : max(0, t)
    }

    private func startTimer() {
        position = computePosition()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
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
