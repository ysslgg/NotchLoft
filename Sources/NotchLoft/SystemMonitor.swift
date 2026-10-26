import Foundation
import IOKit
import IOKit.ps

struct BatteryInfo: Equatable {
    var hasBattery = false
    var percent = 0
    var isCharging = false
    var isPluggedIn = false
    var isFull = false
    var minutes: Int?        // temps restant (sur batterie) ou avant charge complète
    var health: Int?         // % de la capacité d'origine
    var cycles: Int?
}

/// Batterie, processeur, mémoire et disque. Ne mesure que lorsque la page est affichée.
final class SystemMonitor: ObservableObject {
    @Published private(set) var battery = BatteryInfo()
    @Published private(set) var cpu: Double = 0
    @Published private(set) var memoryUsed: Double = 0
    @Published private(set) var memoryTotalGB: Double = 0
    @Published private(set) var memoryUsedGB: Double = 0
    @Published private(set) var diskUsed: Double = 0
    @Published private(set) var diskFreeGB: Double = 0
    @Published private(set) var diskTotalGB: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var thermal = "Normale"

    private var timer: Timer?
    private var lastTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    func start() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTicks = nil
    }

    private func refresh() {
        let b = Self.readBattery()
        if b != battery { battery = b }
        if let c = readCPU() {
            cpu = c
            cpuHistory = Array((cpuHistory + [c]).suffix(40))
        }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Normale"
        case .fair: thermal = "Moyenne"
        case .serious: thermal = "Élevée"
        case .critical: thermal = "Critique"
        @unknown default: thermal = "—"
        }
        readMemory()
        readDisk()
    }

    // MARK: Batterie

    private static func readBattery() -> BatteryInfo {
        var info = BatteryInfo()
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return info }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            info.hasBattery = true
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            info.percent = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            info.isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
            info.isPluggedIn = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            info.isFull = d[kIOPSIsChargedKey] as? Bool ?? false
            let key = info.isPluggedIn ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let m = d[key] as? Int, m > 0 { info.minutes = m }
        }
        if info.hasBattery { readSmartBattery(into: &info) }
        return info
    }

    private static func readSmartBattery(into info: inout BatteryInfo) {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return }
        defer { IOObjectRelease(svc) }
        func int(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        }
        info.cycles = int("CycleCount")
        if let design = int("DesignCapacity"), design > 0, let raw = int("AppleRawMaxCapacity") ?? int("MaxCapacity"), raw > 100 {
            info.health = Swift.min(100, Int((Double(raw) / Double(design) * 100).rounded()))
        } else if let m = int("MaxCapacity"), (1...100).contains(m) {
            info.health = m   // certains Mac donnent directement un pourcentage
        }
    }

    // MARK: Processeur, mémoire, disque

    private func readCPU() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        let t = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { lastTicks = t }
        guard let p = lastTicks else { return nil }
        let du = Double(t.user &- p.user), ds = Double(t.system &- p.system)
        let di = Double(t.idle &- p.idle), dn = Double(t.nice &- p.nice)
        let total = du + ds + di + dn
        return total > 0 ? (du + ds + dn) / total : nil
    }

    private func readMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        memoryTotalGB = total / 1_073_741_824
        memoryUsedGB = used / 1_073_741_824
        memoryUsed = Swift.min(1, used / total)
    }

    private func readDisk() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage, total > 0 else { return }
        diskFreeGB = Double(free) / 1_000_000_000
        diskTotalGB = Double(total) / 1_000_000_000
        diskUsed = 1 - Double(free) / Double(total)
    }
}
