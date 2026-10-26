import AppKit
import Combine
import SwiftUI

/// Panneau sans bordure, transparent et non activant, posé sur l'encoche.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Empêche macOS de repousser la fenêtre sous la barre des menus.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class NotchWindowController {
    private let model: NowPlayingModel
    private let ui = NotchUIState()
    private let panel: NotchPanel
    private var screen: NSScreen?

    private var monitors: [Any] = []
    private var pending: DispatchWorkItem?
    private var pendingTarget: Bool?
    private var settingsObserver: AnyCancellable?

    private let tools: ToolsHub
    private let animator = ArrivalAnimator()
    private var peekUntil = Date.distantPast

    init(model: NowPlayingModel, tools: ToolsHub) {
        self.model = model
        self.tools = tools
        panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: NotchGeometry.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true

        let host = NSHostingView(rootView: NotchRootView(model: model, ui: ui, tools: tools))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: NotchGeometry.panelSize)
        panel.contentView = host
    }

    func start() {
        reposition()
        tools.shelf.arrivalHandler = { [weak self] shot in
            MainActor.assumeIsolated { self?.celebrate(shot) }
        }
        settingsObserver = Settings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.reposition() } }
        }
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseChanged() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.mouseChanged() }
            return e
        }) { monitors.append(m) }
    }

    // MARK: Placement

    private func reposition() {
        guard let (screen, geometry) = NotchGeometry.resolve() else { return }
        self.screen = screen
        ui.geometry = geometry
        let size = NotchGeometry.panelSize
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: Survol

    /// L'encoche s'ouvre s'il y a de la musique, ou à défaut des outils (si le réglage l'autorise).
    private var canExpand: Bool {
        model.isShown || (Settings.shared.hasTools && Settings.shared.openWhenIdle)
    }

    /// Un fichier est en cours de glissement (bouton enfoncé + fichiers sur le presse-papiers de glisser).
    private var isFileDrag: Bool {
        guard Settings.shared.enableFiles, NSEvent.pressedMouseButtons & 1 != 0 else { return false }
        return NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true])
    }

    private func hitRect(expanded: Bool) -> NSRect? {
        guard let screen else { return nil }
        let g = ui.geometry
        var size = expanded
            ? ui.pageSize
            : (model.isShown ? g.compactSize : CGSize(width: g.notchWidth, height: g.notchHeight))
        // Marges : tolérance au bord haut de l'écran, et hystérésis une fois ouvert.
        let pad: CGFloat = expanded ? 10 : 0
        size.width += 2 * pad
        size.height += pad + 4
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height + 4,
                      width: size.width, height: size.height)
    }

    // MARK: Arrivée d'une capture

    /// La miniature vole vers l'encoche, qui s'ouvre sur l'étendoir un instant pour l'accrocher.
    private func celebrate(_ shot: Shot) {
        guard let screen, NotchPage.shelf.isEnabled else {
            tools.shelf.release(shot.url)
            return
        }
        let target = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - ui.geometry.notchHeight / 2)
        animator.fly(image: shot.image, screen: screen, target: target) { [weak self] in
            guard let self else { return }
            self.peekShelf()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.tools.shelf.release(shot.url) }
        }
    }

    private func peekShelf() {
        ui.page = .shelf
        peekUntil = Date().addingTimeInterval(3.2)
        cancelPending()
        setExpanded(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) { [weak self] in
            MainActor.assumeIsolated { self?.mouseChanged() }
        }
    }

    private func mouseChanged() {
        guard Date() >= peekUntil else { return }
        if ui.expanded {
            let m = NSEvent.mouseLocation
            MouseHub.shared.location = CGPoint(x: m.x - panel.frame.minX, y: panel.frame.maxY - m.y)
        }
        let fileDrag = isFileDrag
        guard canExpand || fileDrag else {
            if ui.expanded { schedule(open: false, delay: 0.24) } else { cancelPending() }
            return
        }
        guard let rect = hitRect(expanded: ui.expanded) else { return }
        var inside = rect.contains(NSEvent.mouseLocation)
        // Pendant un glisser (curseur, vignette), on reste ouvert.
        if !inside && ui.expanded && (ui.isScrubbing || NSEvent.pressedMouseButtons != 0) { inside = true }
        // La fenêtre ne capte la souris que sur l'encoche ouverte, jamais autour.
        panel.ignoresMouseEvents = !(ui.expanded && inside)
        // Un fichier qu'on traîne jusqu'à l'encoche ouvre le dépôt.
        if fileDrag, inside, ui.expanded, ui.effectivePage != .files, ui.effectivePage != .shelf { ui.page = .files }
        if inside == ui.expanded {
            cancelPending()
        } else {
            schedule(open: inside, delay: inside ? 0.06 : 0.24)
        }
    }

    private func schedule(open: Bool, delay: TimeInterval) {
        if pendingTarget == open { return }
        cancelPending()
        pendingTarget = open
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.setExpanded(open) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
        pendingTarget = nil
    }

    private func setExpanded(_ value: Bool) {
        pending = nil
        pendingTarget = nil
        guard ui.expanded != value else { return }
        if value, isFileDrag {
            ui.page = .files
        } else if value, !model.isShown, ui.effectivePage == .music,
           let tool = NotchPage.enabled.first(where: { $0 != .music }) {
            ui.page = tool
        }
        ui.expanded = value
        MouseHub.shared.location = CGPoint(x: -10_000, y: -10_000)
        panel.ignoresMouseEvents = !value
        model.tracksPosition = value
        if value && Settings.shared.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }
}
