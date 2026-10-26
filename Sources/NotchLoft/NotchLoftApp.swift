import AppKit
import SwiftUI

@main
struct NotchLoftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some Scene {
        MenuBarExtra {
            Menu {
                Toggle(tr("Clipboard"), isOn: $settings.enableClipboard)
                Toggle(tr("Screenshot shelf"), isOn: $settings.enableShelf)
                Toggle(tr("File tray"), isOn: $settings.enableFiles)
                Toggle(tr("Battery & system"), isOn: $settings.enableSystem)
                Divider()
                Picker(tr("Featured system info"), selection: $settings.systemHero) {
                    ForEach(SystemMetric.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Button(tr("Clear clipboard history")) { ToolsHub.shared.clipboard.clearUnpinned() }
                Button(tr("Retry access to the screenshots folder")) { ToolsHub.shared.shelf.retryAccess() }
            } label: {
                Label(tr("Tools"), systemImage: "square.grid.2x2")
            }

            Menu {
                Picker(tr("Page on open"), selection: $settings.openPage) {
                    Text(tr("Last used")).tag("last")
                    ForEach(NotchPage.enabled) { Text($0.title).tag($0.rawValue) }
                }
                Toggle(tr("Open tools when nothing is playing"), isOn: $settings.openWhenIdle)
                Toggle(tr("Hide in full-screen apps"), isOn: $settings.hideInFullscreen)
                Picker(tr("Hide after a pause"), selection: $settings.idleDelay) {
                    ForEach(IdleDelay.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Label(tr("Opening & display"), systemImage: "rectangle.topthird.inset.filled")
            }

            Menu {
                Picker(tr("Accent color"), selection: $settings.accent) {
                    ForEach(AccentChoice.allCases) { Text($0.label).tag($0) }
                }
                Picker(tr("Idle width"), selection: $settings.compactWidth) {
                    ForEach(CompactWidth.allCases) { Text($0.label).tag($0) }
                }
                Divider()
                Toggle(tr("Animated visualizer"), isOn: $settings.showVisualizer)
                Toggle(tr("Sound-reactive visualizer (permission required)"), isOn: $settings.reactiveVisualizer)
                Toggle(tr("Progress ring"), isOn: $settings.showProgressRing)
                Toggle(tr("Blurred artwork background"), isOn: $settings.blurBackdrop)
            } label: {
                Label(tr("Appearance & music"), systemImage: "paintpalette")
            }

            Menu {
                Toggle(tr("Haptic feedback"), isOn: $settings.haptics)
                Toggle(tr("Animate new screenshots"), isOn: $settings.animateArrivals)
                Toggle(tr("Launch at login"), isOn: $settings.launchAtLogin)
            } label: {
                Label(tr("Behavior"), systemImage: "gearshape")
            }

            Divider()

            if case .available(let version, let url) = updates.state {
                Button(tr("⬆︎ Download version %@", version)) { NSWorkspace.shared.open(url) }
            }
            Menu {
                Button(updates.state == .checking ? tr("Checking…") : tr("Check for updates…")) {
                    updates.check(manual: true)
                }
                .disabled(updates.state == .checking)
                Toggle(tr("Check automatically"), isOn: $settings.autoUpdateCheck)
            } label: {
                Label(tr("Version %@", updates.currentVersion), systemImage: "arrow.triangle.2.circlepath")
            }

            Divider()
            Picker(tr("Language"), selection: $settings.language) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Divider()
            Button(tr("Quit NotchLoft")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: MenuBarIcon.make(badge: updates.hasUpdate))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = NowPlayingModel()
    private var controller: NotchWindowController?
    private var signalSources: [DispatchSourceSignal] = []

    /// Une seule instance à la fois : la plus récente remplace les autres (mise à jour, nouvelle copie).
    /// Deux copies qui se disputent les autorisations macOS (Bureau…) réclamaient la permission en boucle.
    private func replaceOtherInstances() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return }
        others.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, others.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        replaceOtherInstances()
        // Arrêt par `kill` ou fermeture du Moniteur d'activité : on referme proprement l'adaptateur.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }
        NSApp.setActivationPolicy(.accessory)
        controller = NotchWindowController(model: model, tools: ToolsHub.shared)
        controller?.start()
        ToolsHub.shared.start()
        FullscreenDetector.shared.start()
        UpdateChecker.shared.startAutomaticChecks()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        AudioLevels.shared.shutdown()
    }
}
