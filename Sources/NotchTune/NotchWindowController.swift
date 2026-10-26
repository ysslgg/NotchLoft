import AppKit
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

    init(model: NowPlayingModel) {
        self.model = model
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

        let host = NSHostingView(rootView: NotchRootView(model: model, ui: ui))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: NotchGeometry.panelSize)
        panel.contentView = host
    }

    func start() {
        reposition()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
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

    private func hitRect(expanded: Bool) -> NSRect? {
        guard let screen else { return nil }
        let g = ui.geometry
        var size = expanded ? NotchGeometry.expandedSize : g.compactSize
        // Marges : tolérance au bord haut de l'écran, et hystérésis une fois ouvert.
        let pad: CGFloat = expanded ? 10 : 0
        size.width += 2 * pad
        size.height += pad + 4
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height + 4,
                      width: size.width, height: size.height)
    }

    private func mouseChanged() {
        guard model.hasTrack else {
            if ui.expanded { schedule(open: false, delay: 0.24) } else { cancelPending() }
            return
        }
        guard let rect = hitRect(expanded: ui.expanded) else { return }
        var inside = rect.contains(NSEvent.mouseLocation)
        if !inside && ui.isScrubbing { inside = true }
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
        ui.expanded = value
        panel.ignoresMouseEvents = !value
        model.tracksPosition = value
    }
}
