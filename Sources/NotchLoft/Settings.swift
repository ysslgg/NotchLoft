import SwiftUI
import ServiceManagement

enum AccentChoice: String, CaseIterable, Identifiable {
    case auto, pink, blue, green, orange, white
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: tr("From artwork")
        case .pink: tr("Pink")
        case .blue: tr("Blue")
        case .green: tr("Green")
        case .orange: "Orange"
        case .white: tr("White")
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
        case .narrow: tr("Narrow")
        case .normal: tr("Normal")
        case .wide: tr("Wide")
        }
    }
    var side: CGFloat {
        switch self {
        case .narrow: 38
        case .normal: 46
        case .wide: 58
        }
    }
}

enum IdleDelay: String, CaseIterable, Identifiable {
    case never, s15, s45, min2
    var id: String { rawValue }
    var label: String {
        switch self {
        case .never: tr("Never")
        case .s15: tr("15 seconds")
        case .s45: tr("45 seconds")
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
    @Published var autoUpdateCheck: Bool { didSet { d.set(autoUpdateCheck, forKey: "autoUpdateCheck") } }
    @Published var enableFiles: Bool { didSet { d.set(enableFiles, forKey: "enableFiles") } }
    @Published var enableSystem: Bool { didSet { d.set(enableSystem, forKey: "enableSystem") } }
    /// Info système affichée en grand : battery, cpu, memory ou disk.
    @Published var systemHero: String { didSet { d.set(systemHero, forKey: "systemHero") } }
    /// Barres du visualiseur calées sur le vrai son (demande l'autorisation d'écouter le son du Mac).
    @Published var reactiveVisualizer: Bool { didSet { d.set(reactiveVisualizer, forKey: "reactiveVisualizer") } }
    /// Masque l'encoche au repos dans une app en plein écran (elle s'ouvre toujours au survol).
    @Published var hideInFullscreen: Bool { didSet { d.set(hideInFullscreen, forKey: "hideInFullscreen") } }
    /// Page affichée à l'ouverture : « last » (la dernière utilisée) ou le nom d'une page.
    @Published var openPage: String { didSet { d.set(openPage, forKey: "openPage") } }
    /// Langue de l'app : anglais par défaut, français en option.
    @Published var language: AppLanguage { didSet { d.set(language.rawValue, forKey: "language") } }
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
                NSLog("NotchLoft: could not change launch at login: \(error)")
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    var hasTools: Bool { enableClipboard || enableShelf || enableFiles || enableSystem }

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
        openWhenIdle = bool("openWhenIdle")
        animateArrivals = bool("animateArrivals")
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .en
        openPage = d.string(forKey: "openPage") ?? "last"
        hideInFullscreen = bool("hideInFullscreen")
        reactiveVisualizer = bool("reactiveVisualizer")
        systemHero = d.string(forKey: "systemHero") ?? "battery"
        enableFiles = bool("enableFiles")
        enableSystem = bool("enableSystem")
        autoUpdateCheck = bool("autoUpdateCheck")
        accent = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .auto
        compactWidth = CompactWidth(rawValue: d.string(forKey: "compactWidth") ?? "") ?? .normal
        idleDelay = IdleDelay(rawValue: d.string(forKey: "idleDelay") ?? "") ?? .s45
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
