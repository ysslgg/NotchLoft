import AppKit
import CoreAudio
import Darwin

/// Une app qui produit (ou a produit) du son, regroupée avec ses processus d'aide (Chrome Helper…).
struct MixerApp: Identifiable, Equatable {
    let id: String            // chemin du .app
    let name: String
    let icon: NSImage
    let processes: [AudioObjectID]
    let isPlaying: Bool

    static func == (a: MixerApp, b: MixerApp) -> Bool {
        a.id == b.id && a.processes == b.processes && a.isPlaying == b.isPlaying
    }
}

/// Volume par application, sans pilote audio : on « tape » le son de l'app (Core Audio, macOS 14.2+),
/// on coupe sa sortie d'origine et on le rejoue vers la même sortie avec un gain.
/// Le tap n'existe que tant que le volume d'une app diffère de 100 %.
final class AppMixer: ObservableObject {
    @Published private(set) var apps: [MixerApp] = []
    @Published private(set) var volumes: [String: Float] = [:]
    @Published private(set) var muted: Set<String> = []
    @Published private(set) var errorMessage: String?

    private var sessions: [String: AnyObject] = [:]   // TapSession (macOS 14.2+)
    private var timer: Timer?
    private var wantsUI = false
    private var iconCache: [String: NSImage] = [:]

    var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    // MARK: Cycle de vie

    func start() {
        wantsUI = true
        tick()
        schedule()
    }

    func stop() {
        wantsUI = false
        schedule()
    }

    /// Rend le son aux apps (à appeler à la fermeture de NotchLoft).
    func shutdown() {
        if #available(macOS 14.2, *) {
            for case let s as TapSession in sessions.values { s.stop() }
        }
        sessions.removeAll()
    }

    private func schedule() {
        let needed = wantsUI || !sessions.isEmpty
        if needed, timer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !needed {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: Lecture des apps

    func volume(for id: String) -> Float { volumes[id] ?? 1 }
    func isMuted(_ id: String) -> Bool { muted.contains(id) }

    private func tick() {
        guard #available(macOS 14.2, *) else { return }
        let all = readApps()
        let outUID = Self.defaultOutputUID()

        // Garde les sessions à jour : processus qui apparaissent, sortie qui change, app fermée.
        for (id, obj) in sessions {
            guard let session = obj as? TapSession else { continue }
            guard let app = all.first(where: { $0.id == id }) else {
                session.stop(); sessions.removeValue(forKey: id); continue
            }
            // Garde-fou : une app qui joue mais dont on ne reçoit aucun son (autorisation refusée) ne doit pas rester muette.
            if app.isPlaying, session.peak == 0, Date().timeIntervalSince(session.startedAt) > 3 {
                session.stop(); sessions.removeValue(forKey: id)
                volumes.removeValue(forKey: id); muted.remove(id)
                errorMessage = "Aucun son reçu : autorise NotchLoft dans Réglages Système → Confidentialité → Enregistrement audio de l'app."
                continue
            }
            if Set(app.processes) != Set(session.processes) || session.outputUID != outUID {
                session.stop(); sessions.removeValue(forKey: id)
                apply(app)
            }
        }
        // Réapplique un réglage mémorisé à une app qui revient.
        for app in all where sessions[app.id] == nil && effectiveGain(app.id) < 0.999 { apply(app) }

        let visible = all.filter { $0.isPlaying || sessions[$0.id] != nil || volumes[$0.id] != nil || muted.contains($0.id) }
            .sorted { ($0.isPlaying ? 0 : 1, $0.name.lowercased()) < ($1.isPlaying ? 0 : 1, $1.name.lowercased()) }
        if visible != apps { apps = visible }
        schedule()
    }

    private func effectiveGain(_ id: String) -> Float { muted.contains(id) ? 0 : (volumes[id] ?? 1) }

    // MARK: Actions

    func setVolume(_ v: Float, for app: MixerApp) {
        let value = max(0, min(1, v))
        if value >= 0.995 { volumes.removeValue(forKey: app.id) } else { volumes[app.id] = value }
        if value > 0 { muted.remove(app.id) }
        apply(app)
    }

    func toggleMute(_ app: MixerApp) {
        if muted.contains(app.id) { muted.remove(app.id) } else { muted.insert(app.id) }
        apply(app)
    }

    private func apply(_ app: MixerApp) {
        guard #available(macOS 14.2, *) else { return }
        let gain = effectiveGain(app.id)
        if gain >= 0.999 {
            (sessions.removeValue(forKey: app.id) as? TapSession)?.stop()
            schedule()
            return
        }
        if let s = sessions[app.id] as? TapSession {
            s.gain = gain
            return
        }
        guard !app.processes.isEmpty, let uid = Self.defaultOutputUID() else { return }
        do {
            sessions[app.id] = try TapSession(processes: app.processes, outputUID: uid, gain: gain)
            errorMessage = nil
        } catch {
            volumes.removeValue(forKey: app.id)
            muted.remove(app.id)
            errorMessage = "Impossible de régler cette app : autorise NotchLoft dans Réglages Système → Confidentialité → Enregistrement audio de l'app."
        }
        schedule()
    }

    // MARK: Énumération CoreAudio

    private func readApps() -> [MixerApp] {
        var groups: [String: (processes: [AudioObjectID], playing: Bool)] = [:]
        let me = getpid()
        for obj in Self.processObjects() {
            guard let pid = Self.u32(obj, 0x7070_6964 /* 'ppid' */), pid_t(pid) != me,
                  let path = Self.appPath(forPID: pid_t(pid)) else { continue }
            let playing = (Self.u32(obj, 0x7069_726F /* 'piro' */) ?? 0) != 0
            var g = groups[path] ?? ([], false)
            g.processes.append(obj)
            g.playing = g.playing || playing
            groups[path] = g
        }
        return groups.map { path, g in
            MixerApp(id: path, name: FileManager.default.displayName(atPath: path), icon: icon(for: path),
                     processes: g.processes.sorted(), isPlaying: g.playing)
        }
    }

    private func icon(for path: String) -> NSImage {
        if let i = iconCache[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = i
        return i
    }

    private static func processObjects() -> [AudioObjectID] {
        var a = AudioObjectPropertyAddress(mSelector: 0x7072_7323 /* 'prs#' */, mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func u32(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr else { return nil }
        return v
    }

    /// Chemin du .app le plus externe qui contient l'exécutable (Chrome Helper → Google Chrome.app).
    private static func appPath(forPID pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        let comps = String(cString: buf).split(separator: "/", omittingEmptySubsequences: true)
        guard let idx = comps.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + comps[0...idx].joined(separator: "/")
    }

    static func defaultOutputUID() -> String? {
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

// MARK: - Tap

struct TapError: Error { let status: OSStatus }

/// Un tap sur les processus d'une app, relié à un appareil agrégé privé qui rejoue le son avec un gain.
@available(macOS 14.2, *)
final class TapSession {
    let processes: [AudioObjectID]
    let outputUID: String?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let gainPtr = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private let peakPtr = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let startedAt = Date()
    private let queue = DispatchQueue(label: "notchloft.tap", qos: .userInteractive)
    private var stopped = false

    /// Plus fort échantillon reçu depuis le début : 0 = aucun son capté (autorisation refusée ?).
    var peak: Float { peakPtr.pointee }

    var gain: Float {
        get { gainPtr.pointee }
        set { gainPtr.pointee = newValue }
    }

    init(processes: [AudioObjectID], outputUID: String, gain: Float) throws {
        self.processes = processes
        self.outputUID = outputUID
        gainPtr.initialize(to: gain)
        peakPtr.initialize(to: 0)

        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true
        var status = AudioHardwareCreateProcessTap(desc, &tapID)
        guard status == noErr else { gainPtr.deallocate(); peakPtr.deallocate(); throw TapError(status: status) }

        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchLoft Mixer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
        guard status == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            gainPtr.deallocate(); peakPtr.deallocate()
            throw TapError(status: status)
        }

        let gp = gainPtr, pp = peakPtr
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue) { _, inData, _, outData, _ in
            TapSession.render(input: inData, output: outData, gain: gp.pointee, peak: pp)
        }
        guard status == noErr else { stop(); throw TapError(status: status) }
        status = AudioDeviceStart(aggID, procID)
        guard status == noErr else { stop(); throw TapError(status: status) }
    }

    /// Copie le son capté vers la sortie en le multipliant par le gain (Float32, entrelacé ou non).
    private static func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, gain: Float,
                               peak: UnsafeMutablePointer<Float>) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outs = UnsafeMutableAudioBufferListPointer(output)
        for b in 0..<outs.count {
            guard let dst = outs[b].mData?.assumingMemoryBound(to: Float.self) else { continue }
            let outCh = max(1, Int(outs[b].mNumberChannels))
            let outFrames = Int(outs[b].mDataByteSize) / (MemoryLayout<Float>.size * outCh)
            guard ins.count > 0, let src = ins[min(b, ins.count - 1)].mData?.assumingMemoryBound(to: Float.self) else {
                memset(dst, 0, Int(outs[b].mDataByteSize))
                continue
            }
            let inBuf = ins[min(b, ins.count - 1)]
            let inCh = max(1, Int(inBuf.mNumberChannels))
            let inFrames = Int(inBuf.mDataByteSize) / (MemoryLayout<Float>.size * inCh)
            let frames = min(inFrames, outFrames)
            for f in 0..<frames {
                for c in 0..<outCh {
                    let x = src[f * inCh + min(c, inCh - 1)]
                    if abs(x) > peak.pointee { peak.pointee = abs(x) }
                    dst[f * outCh + c] = x * gain
                }
            }
            if frames < outFrames {
                memset(dst.advanced(by: frames * outCh), 0, (outFrames - frames) * outCh * MemoryLayout<Float>.size)
            }
        }
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
        gainPtr.deallocate(); peakPtr.deallocate()
    }

    deinit { stop() }
}
