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
/// Toutes les valeurs sont regroupées et arrondies : la vue n'est mise à jour que si quelque chose change.
final class SystemMonitor: ObservableObject {
    struct Stats: Equatable {
        var battery = BatteryInfo()
        var cpu: Double = 0
        var memoryUsed: Double = 0
        var memoryTotalGB: Double = 0
        var memoryUsedGB: Double = 0
        var diskUsed: Double = 0
        var diskFreeGB: Double = 0
        var diskTotalGB: Double = 0
        var cpuHistory: [Double] = []
        var thermal = tr("Normal")
    }

    @Published private(set) var stats = Stats()

    var battery: BatteryInfo { stats.battery }
    var cpu: Double { stats.cpu }
    var memoryUsed: Double { stats.memoryUsed }
    var memoryTotalGB: Double { stats.memoryTotalGB }
    var memoryUsedGB: Double { stats.memoryUsedGB }
    var diskUsed: Double { stats.diskUsed }
    var diskFreeGB: Double { stats.diskFreeGB }
    var diskTotalGB: Double { stats.diskTotalGB }
    var cpuHistory: [Double] { stats.cpuHistory }
    var thermal: String { stats.thermal }

    /// La courbe du processeur n'est conservée (et redessinée) que si elle est affichée.
    var trackHistory = false

    private var timer: Timer?
    private var lastTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var smart: (cycles: Int?, health: Int?)?
    private var smartDate = Date.distantPast

    func start() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 0.4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTicks = nil
    }

    private func refresh() {
        var n = stats
        n.battery = Self.readBattery()
        // Cycles et santé changent très lentement : on ne les relit qu'une fois par minute.
        if n.battery.hasBattery {
            if smart == nil || Date().timeIntervalSince(smartDate) > 60 {
                smart = Self.readSmartBattery()
                smartDate = Date()
            }
            n.battery.cycles = smart?.cycles
            n.battery.health = smart?.health
        }
        if let c = readCPU() {
            n.cpu = (c * 100).rounded() / 100
            if trackHistory { n.cpuHistory = Array((n.cpuHistory + [c]).suffix(40)) }
        }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: n.thermal = tr("Normal")
        case .fair: n.thermal = tr("Fair")
        case .serious: n.thermal = tr("Serious")
        case .critical: n.thermal = tr("Critical")
        @unknown default: n.thermal = "—"
        }
        readMemory(into: &n)
        readDisk(into: &n)
        if n != stats { stats = n }
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
        return info
    }

    private static func readSmartBattery() -> (cycles: Int?, health: Int?) {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return (nil, nil) }
        defer { IOObjectRelease(svc) }
        func int(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
        }
        var health: Int?
        if let design = int("DesignCapacity"), design > 0, let raw = int("AppleRawMaxCapacity") ?? int("MaxCapacity"), raw > 100 {
            health = Swift.min(100, Int((Double(raw) / Double(design) * 100).rounded()))
        } else if let m = int("MaxCapacity"), (1...100).contains(m) {
            health = m   // certains Mac donnent directement un pourcentage
        }
        return (int("CycleCount"), health)
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

    private func readMemory(into n: inout Stats) {
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
        n.memoryTotalGB = total / 1_073_741_824
        n.memoryUsedGB = ((used / 1_073_741_824) * 10).rounded() / 10
        n.memoryUsed = (Swift.min(1, used / total) * 100).rounded() / 100
    }

    private func readDisk(into n: inout Stats) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage, total > 0 else { return }
        n.diskFreeGB = (Double(free) / 1_000_000_000).rounded()
        n.diskTotalGB = (Double(total) / 1_000_000_000).rounded()
        n.diskUsed = ((1 - Double(free) / Double(total)) * 100).rounded() / 100
    }
}
