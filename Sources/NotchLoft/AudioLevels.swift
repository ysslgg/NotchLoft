import Accelerate
import AppKit
import CoreAudio

/// Niveaux (0...1) de cinq bandes de fréquences du son joué par le Mac, pour le visualiseur.
/// Le son est écouté en lecture seule (Core Audio, macOS 14.2+), jamais enregistré ni modifié :
/// seuls ces cinq nombres sortent de l'analyse.
final class AudioLevels {
    static let shared = AudioLevels()
    static let bandCount = 5

    private let levels = UnsafeMutablePointer<Float>.allocate(capacity: bandCount)
    private let lastSound = UnsafeMutablePointer<Double>.allocate(capacity: 1)
    private var listener: AnyObject?
    private var wanted = false

    private init() {
        levels.initialize(repeating: 0, count: Self.bandCount)
        lastSound.initialize(to: 0)
    }

    func level(_ band: Int) -> Float { levels[band] }

    /// Vrai si du son a été reçu à l'instant : sinon le visualiseur reste décoratif.
    var isLive: Bool {
        let t = lastSound.pointee
        return t > 0 && Date().timeIntervalSinceReferenceDate - t < 1.0
    }

    /// À appeler quand la lecture démarre ou s'arrête, ou quand le réglage change.
    func setWanted(_ playing: Bool) {
        wanted = playing
        refresh()
    }

    func refresh() {
        let shouldRun = wanted && Settings.shared.reactiveVisualizer
        if #available(macOS 14.2, *) {
            if shouldRun, listener == nil {
                do {
                    listener = try TapListener(levels: levels, lastSound: lastSound)
                } catch {
                    NSLog("NotchLoft: could not listen to system audio (\(error))")
                }
            } else if !shouldRun, let l = listener as? TapListener {
                l.stop()
                listener = nil
                levels.update(repeating: 0, count: Self.bandCount)
                lastSound.pointee = 0
            }
        }
    }

    func shutdown() {
        if #available(macOS 14.2, *) { (listener as? TapListener)?.stop() }
        listener = nil
    }

    fileprivate static func defaultOutputUID() -> String? {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev) == noErr, dev != 0 else { return nil }
        var u = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &u, 0, nil, &s, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}

struct ListenError: Error { let status: OSStatus }

/// Branchement en lecture seule sur tout le son du Mac (aucune sortie modifiée).
@available(macOS 14.2, *)
final class TapListener {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "notchloft.listen", qos: .userInteractive)
    private let analyzer: SpectrumAnalyzer
    private var stopped = false

    init(levels: UnsafeMutablePointer<Float>, lastSound: UnsafeMutablePointer<Double>) throws {
        analyzer = SpectrumAnalyzer(levels: levels, lastSound: lastSound)
        guard let uid = AudioLevels.defaultOutputUID() else { throw ListenError(status: -1) }

        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        var status = AudioHardwareCreateProcessTap(desc, &tapID)
        guard status == noErr else { throw ListenError(status: status) }

        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchLoft Listener",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
        guard status == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw ListenError(status: status)
        }

        var rateAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                                  mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate = Float64(48_000)
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(aggID, &rateAddr, 0, nil, &size, &rate)
        analyzer.sampleRate = Float(rate)

        let a = analyzer
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue) { _, inData, _, outData, _ in
            // On n'émet que du silence : le son réel suit son chemin normal vers les haut-parleurs.
            for b in UnsafeMutableAudioBufferListPointer(outData) {
                if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) }
            }
            a.process(input: inData)
        }
        guard status == noErr else { stop(); throw ListenError(status: status) }
        status = AudioDeviceStart(aggID, procID)
        guard status == noErr else { stop(); throw ListenError(status: status) }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        if let p = procID, aggID != kAudioObjectUnknown {
            AudioDeviceStop(aggID, p)
            AudioDeviceDestroyIOProcID(aggID, p)
        }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        analyzer.teardown()
    }

    deinit { stop() }
}

/// Transformée de Fourier rapide sur 1024 échantillons (avancée de 512), regroupée en 5 bandes.
final class SpectrumAnalyzer {
    var sampleRate: Float = 48_000
    private static let debug = ProcessInfo.processInfo.environment["NOTCHLOFT_DEBUG_LEVELS"] != nil
    private var debugCount = 0

    private let n = 1024
    private let hop = 512
    private let log2n: vDSP_Length = 10
    private var fft: FFTSetup?
    private var window: [Float]
    private var ring: [Float]
    private var write = 0
    private var sinceLast = 0
    private var real: [Float]
    private var imag: [Float]
    private var ordered: [Float]
    private var power: [Float]
    private var smooth = [Float](repeating: 0, count: AudioLevels.bandCount)
    private let levels: UnsafeMutablePointer<Float>
    private let lastSound: UnsafeMutablePointer<Double>

    /// Bornes des bandes (Hz) et compensation (dB) : la musique est bien plus forte dans les graves.
    private let edges: [Float] = [40, 160, 500, 1800, 5500, 16000]
    private let tilt: [Float] = [0, 3, 7, 11, 15]

    init(levels: UnsafeMutablePointer<Float>, lastSound: UnsafeMutablePointer<Double>) {
        self.levels = levels
        self.lastSound = lastSound
        fft = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))
        window = [Float](repeating: 0, count: 1024)
        vDSP_hann_window(&window, 1024, Int32(vDSP_HANN_NORM))
        ring = [Float](repeating: 0, count: 1024)
        real = [Float](repeating: 0, count: 512)
        imag = [Float](repeating: 0, count: 512)
        ordered = [Float](repeating: 0, count: 1024)
        power = [Float](repeating: 0, count: 512)
    }

    func teardown() {
        if let f = fft { vDSP_destroy_fftsetup(f) }
        fft = nil
    }

    /// Appelé depuis le fil audio : pas d'allocation ni de verrou.
    func process(input: UnsafePointer<AudioBufferList>) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard list.count > 0, let first = list[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let ch0 = max(1, Int(list[0].mNumberChannels))
        let frames = Int(list[0].mDataByteSize) / (MemoryLayout<Float>.size * ch0)
        let second = list.count > 1 ? list[1].mData?.assumingMemoryBound(to: Float.self) : nil
        for f in 0..<frames {
            var s: Float
            if ch0 >= 2 {
                s = 0.5 * (first[f * ch0] + first[f * ch0 + 1])        // entrelacé
            } else if let b = second {
                s = 0.5 * (first[f] + b[f])                            // un buffer par canal
            } else {
                s = first[f]
            }
            ring[write] = s
            write = (write + 1) & (n - 1)
            sinceLast += 1
            if sinceLast >= hop {
                sinceLast = 0
                analyze()
            }
        }
    }

    private func analyze() {
        guard let fft else { return }
        // Remet les échantillons dans l'ordre chronologique et applique la fenêtre.
        for i in 0..<n { ordered[i] = ring[(write + i) & (n - 1)] }
        vDSP_vmul(ordered, 1, window, 1, &ordered, 1, vDSP_Length(n))
        ordered.withUnsafeBufferPointer { p in
            real.withUnsafeMutableBufferPointer { r in
                imag.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                    p.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                    vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
                }
            }
        }
        let binHz = sampleRate / Float(n)
        var loud = false
        for b in 0..<AudioLevels.bandCount {
            let lo = max(1, Int(edges[b] / binHz)), hi = max(lo + 1, min(n / 2, Int(edges[b + 1] / binHz)))
            var sum: Float = 0
            for k in lo..<hi { sum += power[k] }
            let amp = sqrt(sum / Float(hi - lo)) / Float(n)              // ≈ amplitude d'une sinusoïde
            let db = 20 * log10(amp + 1e-9) + tilt[b]
            let target = min(1, max(0, (db + 72) / 42))
            let k: Float = target > smooth[b] ? 0.65 : 0.18               // attaque rapide, retombée douce
            smooth[b] += (target - smooth[b]) * k
            levels[b] = smooth[b]
            if smooth[b] > 0.03 { loud = true }
        }
        if loud { lastSound.pointee = Date().timeIntervalSinceReferenceDate }
        if Self.debug {
            debugCount += 1
            if debugCount % 43 == 0 {
                NSLog("bands: " + smooth.map { String(format: "%.2f", $0) }.joined(separator: " "))
            }
        }
    }
}
