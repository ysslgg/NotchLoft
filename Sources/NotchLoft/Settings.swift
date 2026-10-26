import SwiftUI
import ServiceManagement

enum AccentChoice: String, CaseIterable, Identifiable {
    case auto, pink, blue, green, orange, white
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "Selon la pochette"
        case .pink: "Rose"
        case .blue: "Bleu"
        case .green: "Vert"
        case .orange: "Orange"
        case .white: "Blanc"
        }
    }
    var color: Color? {
        switch self {
        case .auto: nil
        case .pink: Color(hue: 0.92, saturation: 0.6, brightness: 1)
        case .blue: Color(hue: 0.58, saturation: 0.65, brightness: 1)
        case .green: Color(hue: 0.38, saturation: 0.65, brightness: 0.95)
        case .orange: Color(hue: 0.08, saturation: 0.75, brightness: 1)
        case .white: Color(white: 0.95)
        }
    }
}

enum CompactWidth: String, CaseIterable, Identifiable {
    case narrow, normal, wide
    var id: String { rawValue }
    var label: String {
        switch self {
        case .narrow: "Étroite"
        case .normal: "Normale"
        case .wide: "Large"
        }
    }
    var side: CGFloat {
        switch self {
        case .narrow: 32
        case .normal: 40
        case .wide: 52
        }
    }
}

enum IdleDelay: String, CaseIterable, Identifiable {
    case never, s15, s45, min2
    var id: String { rawValue }
    var label: String {
        switch self {
        case .never: "Jamais"
        case .s15: "15 secondes"
        case .s45: "45 secondes"
        case .min2: "2 minutes"
        }
    }
    var seconds: TimeInterval? {
        switch self {
        case .never: nil
        case .s15: 15
        case .s45: 45
        case .min2: 120
        }
    }
}

/// Réglages personnalisables, enregistrés dans UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    @Published var showVisualizer: Bool { didSet { d.set(showVisualizer, forKey: "showVisualizer") } }
    @Published var showProgressRing: Bool { didSet { d.set(showProgressRing, forKey: "showProgressRing") } }
    @Published var blurBackdrop: Bool { didSet { d.set(blurBackdrop, forKey: "blurBackdrop") } }
    @Published var enableClipboard: Bool { didSet { d.set(enableClipboard, forKey: "enableClipboard") } }
    @Published var enableShelf: Bool { didSet { d.set(enableShelf, forKey: "enableShelf") } }
    @Published var enableAudio: Bool { didSet { d.set(enableAudio, forKey: "enableAudio") } }
    @Published var animateArrivals: Bool { didSet { d.set(animateArrivals, forKey: "animateArrivals") } }
    @Published var openWhenIdle: Bool { didSet { d.set(openWhenIdle, forKey: "openWhenIdle") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    @Published var accent: AccentChoice { didSet { d.set(accent.rawValue, forKey: "accent") } }
    @Published var compactWidth: CompactWidth { didSet { d.set(compactWidth.rawValue, forKey: "compactWidth") } }
    @Published var idleDelay: IdleDelay { didSet { d.set(idleDelay.rawValue, forKey: "idleDelay") } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("NotchLoft: lancement au démarrage impossible: \(error)")
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    var hasTools: Bool { enableClipboard || enableShelf || enableAudio }

    var compactSide: CGFloat { compactWidth.side }

    private init() {
        let d = UserDefaults.standard
        func bool(_ key: String) -> Bool { d.object(forKey: key) as? Bool ?? true }
        showVisualizer = bool("showVisualizer")
        showProgressRing = bool("showProgressRing")
        blurBackdrop = bool("blurBackdrop")
        haptics = bool("haptics")
        enableClipboard = bool("enableClipboard")
        enableShelf = bool("enableShelf")
        enableAudio = bool("enableAudio")
        openWhenIdle = bool("openWhenIdle")
        animateArrivals = bool("animateArrivals")
        accent = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .auto
        compactWidth = CompactWidth(rawValue: d.string(forKey: "compactWidth") ?? "") ?? .normal
        idleDelay = IdleDelay(rawValue: d.string(forKey: "idleDelay") ?? "") ?? .s45
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
