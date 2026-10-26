import AppKit
import SwiftUI

@main
struct NotchLoftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some Scene {
        MenuBarExtra {
            Toggle("Visualiseur animé", isOn: $settings.showVisualizer)
            Toggle("Bague de progression", isOn: $settings.showProgressRing)
            Toggle("Fond flou de la pochette", isOn: $settings.blurBackdrop)
            Toggle("Retour haptique", isOn: $settings.haptics)
            Divider()
            Toggle("Outil : presse-papier", isOn: $settings.enableClipboard)
            Toggle("Outil : étendoir à captures", isOn: $settings.enableShelf)
            Toggle("Outil : dépôt de fichiers", isOn: $settings.enableFiles)
            Toggle("Outil : batterie et système", isOn: $settings.enableSystem)
            Toggle("Animer l'arrivée des captures", isOn: $settings.animateArrivals)
            Toggle("Ouvrir les outils quand rien ne joue", isOn: $settings.openWhenIdle)
            Button("Vider le presse-papier") { ToolsHub.shared.clipboard.clearUnpinned() }
            Divider()
            Picker("Info système en grand", selection: $settings.systemHero) {
                ForEach(SystemMetric.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Couleur d'accent", selection: $settings.accent) {
                ForEach(AccentChoice.allCases) { Text($0.label).tag($0) }
            }
            Picker("Largeur au repos", selection: $settings.compactWidth) {
                ForEach(CompactWidth.allCases) { Text($0.label).tag($0) }
            }
            Picker("Masquer après une pause", selection: $settings.idleDelay) {
                ForEach(IdleDelay.allCases) { Text($0.label).tag($0) }
            }
            Divider()
            Toggle("Lancer au démarrage", isOn: $settings.launchAtLogin)
            Divider()
            Button(updates.state == .checking ? "Recherche en cours…" : "Rechercher des mises à jour…") {
                updates.check(manual: true)
            }
            .disabled(updates.state == .checking)
            if case .available(let version, let url) = updates.state {
                Button("⬆︎ Télécharger la version \(version)") { NSWorkspace.shared.open(url) }
            }
            Toggle("Vérifier automatiquement", isOn: $settings.autoUpdateCheck)
            Text("Version \(updates.currentVersion)")
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = NotchWindowController(model: model, tools: ToolsHub.shared)
        controller?.start()
        ToolsHub.shared.start()
        UpdateChecker.shared.startAutomaticChecks()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
