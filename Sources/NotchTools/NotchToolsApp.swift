import AppKit
import SwiftUI

@main
struct NotchToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @ObservedObject private var settings = Settings.shared

    var body: some Scene {
        MenuBarExtra {
            Toggle("Visualiseur animé", isOn: $settings.showVisualizer)
            Toggle("Bague de progression", isOn: $settings.showProgressRing)
            Toggle("Fond flou de la pochette", isOn: $settings.blurBackdrop)
            Toggle("Retour haptique", isOn: $settings.haptics)
            Divider()
            Toggle("Outil : presse-papier", isOn: $settings.enableClipboard)
            Toggle("Outil : étendoir à captures", isOn: $settings.enableShelf)
            Toggle("Outil : mixeur audio", isOn: $settings.enableAudio)
            Toggle("Animer l'arrivée des captures", isOn: $settings.animateArrivals)
            Toggle("Ouvrir les outils quand rien ne joue", isOn: $settings.openWhenIdle)
            Button("Vider le presse-papier") { ToolsHub.shared.clipboard.clearUnpinned() }
            Divider()
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
            Button("Quitter NotchTools") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: MenuBarIcon.make())
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
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
