import AppKit
import SwiftUI

@main
struct NotchTuneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @ObservedObject private var settings = Settings.shared

    var body: some Scene {
        MenuBarExtra {
            Toggle("Visualiseur animé", isOn: $settings.showVisualizer)
            Toggle("Bague de progression", isOn: $settings.showProgressRing)
            Toggle("Fond flou de la pochette", isOn: $settings.blurBackdrop)
            Toggle("Retour haptique", isOn: $settings.haptics)
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
            Button("Quitter NotchTune") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Text("♪")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = NowPlayingModel()
    private var controller: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = NotchWindowController(model: model)
        controller?.start()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}
