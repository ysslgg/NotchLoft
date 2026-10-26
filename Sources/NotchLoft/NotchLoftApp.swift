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
                Toggle("Presse-papier", isOn: $settings.enableClipboard)
                Toggle("Étendoir à captures", isOn: $settings.enableShelf)
                Toggle("Dépôt de fichiers", isOn: $settings.enableFiles)
                Toggle("Batterie et système", isOn: $settings.enableSystem)
                Divider()
                Picker("Info système en grand", selection: $settings.systemHero) {
                    ForEach(SystemMetric.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Button("Vider le presse-papier") { ToolsHub.shared.clipboard.clearUnpinned() }
                Button("Réessayer l'accès au dossier des captures") { ToolsHub.shared.shelf.retryAccess() }
            } label: {
                Label("Outils", systemImage: "square.grid.2x2")
            }

            Menu {
                Picker("Page à l'ouverture", selection: $settings.openPage) {
                    Text("Dernière utilisée").tag("last")
                    ForEach(NotchPage.enabled) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Ouvrir les outils quand rien ne joue", isOn: $settings.openWhenIdle)
                Toggle("Se masquer dans les apps en plein écran", isOn: $settings.hideInFullscreen)
                Picker("Masquer après une pause", selection: $settings.idleDelay) {
                    ForEach(IdleDelay.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Label("Ouverture et affichage", systemImage: "rectangle.topthird.inset.filled")
            }

            Menu {
                Picker("Couleur d'accent", selection: $settings.accent) {
                    ForEach(AccentChoice.allCases) { Text($0.label).tag($0) }
                }
                Picker("Largeur au repos", selection: $settings.compactWidth) {
                    ForEach(CompactWidth.allCases) { Text($0.label).tag($0) }
                }
                Divider()
                Toggle("Visualiseur animé", isOn: $settings.showVisualizer)
                Toggle("Visualiseur réactif au son (autorisation requise)", isOn: $settings.reactiveVisualizer)
                Toggle("Bague de progression", isOn: $settings.showProgressRing)
                Toggle("Fond flou de la pochette", isOn: $settings.blurBackdrop)
            } label: {
                Label("Apparence et musique", systemImage: "paintpalette")
            }

            Menu {
                Toggle("Retour haptique", isOn: $settings.haptics)
                Toggle("Animer l'arrivée des captures", isOn: $settings.animateArrivals)
                Toggle("Lancer au démarrage", isOn: $settings.launchAtLogin)
            } label: {
                Label("Comportement", systemImage: "gearshape")
            }

            Divider()

            if case .available(let version, let url) = updates.state {
                Button("⬆︎ Télécharger la version \(version)") { NSWorkspace.shared.open(url) }
            }
            Menu {
                Button(updates.state == .checking ? "Recherche en cours…" : "Rechercher des mises à jour…") {
                    updates.check(manual: true)
                }
                .disabled(updates.state == .checking)
                Toggle("Vérifier automatiquement", isOn: $settings.autoUpdateCheck)
            } label: {
                Label("Version \(updates.currentVersion)", systemImage: "arrow.triangle.2.circlepath")
            }

            Divider()
            Button("Quitter NotchLoft") { NSApp.terminate(nil) }
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
