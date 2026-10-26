import CoreAudio
import Foundation

struct AudioDev: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let symbol: String
}

/// Volume, sourdine et périphériques audio du Mac (sortie et entrée) via CoreAudio.
final class AudioMixer: ObservableObject {
    @Published private(set) var outputs: [AudioDev] = []
    @Published private(set) var inputs: [AudioDev] = []
    @Published private(set) var currentOutput: AudioDeviceID = 0
    @Published private(set) var currentInput: AudioDeviceID = 0
    @Published private(set) var outVolume: Float = 0
    @Published private(set) var outVolumeAvailable = false
    @Published private(set) var outMuted = false
    @Published private(set) var inVolume: Float = 0
    @Published private(set) var inVolumeAvailable = false

    private var timer: Timer?
    private var draggingOut = false
    private var draggingIn = false

    /// Rafraîchit tant que la page audio est affichée.
    func start() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Lecture

    func refresh() {
        let devices = Self.allDevices()
        let outs = devices.filter { Self.channels($0, input: false) > 0 }.map(Self.describe)
        let ins = devices.filter { Self.channels($0, input: true) > 0 }.map(Self.describe)
        if outs != outputs { outputs = outs }
        if ins != inputs { inputs = ins }

        let out = Self.defaultDevice(input: false)
        let inp = Self.defaultDevice(input: true)
        if out != currentOutput { currentOutput = out }
        if inp != currentInput { currentInput = inp }

        if let v = Self.volume(out, input: false) {
            outVolumeAvailable = true
            if !draggingOut { outVolume = v }
        } else {
            outVolumeAvailable = false
        }
        outMuted = Self.isMuted(out)
        if let v = Self.volume(inp, input: true) {
            inVolumeAvailable = true
            if !draggingIn { inVolume = v }
        } else {
            inVolumeAvailable = false
        }
    }

    // MARK: Actions

    func setOutputVolume(_ v: Float, dragging: Bool) {
        draggingOut = dragging
        outVolume = v
        Self.setVolume(currentOutput, v, input: false)
        if v > 0, outMuted { setMuted(false) }
    }

    func setInputVolume(_ v: Float, dragging: Bool) {
        draggingIn = dragging
        inVolume = v
        Self.setVolume(currentInput, v, input: true)
    }

    func toggleMute() { setMuted(!outMuted) }

    private func setMuted(_ m: Bool) {
        var a = Self.addr(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        var v: UInt32 = m ? 1 : 0
        if AudioObjectHasProperty(currentOutput, &a) {
            AudioObjectSetPropertyData(currentOutput, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
            outMuted = m
        }
    }

    func selectOutput(_ d: AudioDev) { Self.setDefault(d.id, input: false); refresh() }
    func selectInput(_ d: AudioDev) { Self.setDefault(d.id, input: true); refresh() }

    // MARK: CoreAudio

    private static func addr(_ sel: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                             element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
    }

    private static func allDevices() -> [AudioDeviceID] {
        var a = addr(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            var h = addr(kAudioDevicePropertyIsHidden)
            var hidden: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &h, 0, nil, &s, &hidden) == noErr { return hidden == 0 }
            return true
        }
    }

    private static func channels(_ id: AudioDeviceID, input: Bool) -> Int {
        var a = addr(kAudioDevicePropertyStreamConfiguration,
                     scope: input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func describe(_ id: AudioDeviceID) -> AudioDev {
        var a = addr(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let ok = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &name) == noErr
        let title = ok ? (name?.takeRetainedValue() as String?) ?? "Appareil" : "Appareil"

        var t = addr(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var ts = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &t, 0, nil, &ts, &transport)
        let symbol: String
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: symbol = "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: symbol = "headphones"
        case kAudioDeviceTransportTypeAirPlay: symbol = "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: symbol = "tv"
        case kAudioDeviceTransportTypeUSB: symbol = "cable.connector"
        default: symbol = "hifispeaker"
        }
        return AudioDev(id: id, name: title, symbol: symbol)
    }

    private static func defaultDevice(input: Bool) -> AudioDeviceID {
        var a = addr(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    private static func setDefault(_ id: AudioDeviceID, input: Bool) {
        var dev = id
        let sels = input
            ? [kAudioHardwarePropertyDefaultInputDevice]
            : [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice]
        for s in sels {
            var a = addr(s)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                                       UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
        }
    }

    /// Volume virtuel principal si disponible, sinon moyenne des canaux 1 et 2.
    private static func volume(_ id: AudioDeviceID, input: Bool) -> Float? {
        guard id != 0 else { return nil }
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        var candidates: [AudioObjectPropertyAddress] = []
        if !input { candidates.append(addr(0x766D_7663 /* 'vmvc' */, scope: scope)) }
        candidates.append(addr(kAudioDevicePropertyVolumeScalar, scope: scope, element: 0))
        for var a in candidates where AudioObjectHasProperty(id, &a) {
            var v: Float32 = 0
            var s = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v) == noErr { return v }
        }
        var vals: [Float] = []
        for ch: UInt32 in [1, 2] {
            var a = addr(kAudioDevicePropertyVolumeScalar, scope: scope, element: ch)
            guard AudioObjectHasProperty(id, &a) else { continue }
            var v: Float32 = 0
            var s = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v) == noErr { vals.append(v) }
        }
        return vals.isEmpty ? nil : vals.reduce(0, +) / Float(vals.count)
    }

    private static func setVolume(_ id: AudioDeviceID, _ value: Float, input: Bool) {
        guard id != 0 else { return }
        var v = max(0, min(1, value))
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        var candidates: [AudioObjectPropertyAddress] = []
        if !input { candidates.append(addr(0x766D_7663, scope: scope)) }
        candidates.append(addr(kAudioDevicePropertyVolumeScalar, scope: scope, element: 0))
        for var a in candidates where AudioObjectHasProperty(id, &a) {
            var settable: DarwinBoolean = false
            AudioObjectIsPropertySettable(id, &a, &settable)
            if settable.boolValue,
               AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr { return }
        }
        for ch: UInt32 in [1, 2] {
            var a = addr(kAudioDevicePropertyVolumeScalar, scope: scope, element: ch)
            if AudioObjectHasProperty(id, &a) {
                AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
            }
        }
    }

    private static func isMuted(_ id: AudioDeviceID) -> Bool {
        var a = addr(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        guard id != 0, AudioObjectHasProperty(id, &a) else { return false }
        var v: UInt32 = 0
        var s = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &v) == noErr else { return false }
        return v != 0
    }
}
