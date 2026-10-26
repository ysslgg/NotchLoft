import Combine
import Foundation

/// Regroupe les outils et active/désactive leur surveillance selon les réglages.
final class ToolsHub {
    static let shared = ToolsHub()

    let clipboard = ClipboardStore()
    let shelf = ScreenshotShelf()

    private var observer: AnyCancellable?
    private var current: (Bool, Bool) = (false, false)

    func start() {
        apply()
        observer = Settings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.apply() }
        }
    }

    private func apply() {
        let s = Settings.shared
        let wanted = (s.enableClipboard, s.enableShelf)
        if wanted.0 != current.0 || timerStateUnset { clipboard.setEnabled(wanted.0) }
        if wanted.1 != current.1 || timerStateUnset { shelf.setEnabled(wanted.1) }
        current = wanted
        timerStateUnset = false
    }

    private var timerStateUnset = true
}
