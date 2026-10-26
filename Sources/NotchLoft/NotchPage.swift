import SwiftUI

/// Pages de l'encoche : la musique et les outils.
enum NotchPage: String, CaseIterable, Identifiable {
    case music, clipboard, shelf, files, system

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "photo.on.rectangle.angled"
        case .files: "tray.and.arrow.down"
        case .system: "battery.75percent"
        }
    }

    var title: String {
        switch self {
        case .music: tr("Music")
        case .clipboard: tr("Clipboard")
        case .shelf: tr("Shelf")
        case .files: tr("File tray")
        case .system: tr("Battery & system")
        }
    }

    /// Taille de l'encoche ouverte sur cette page.
    var size: CGSize {
        switch self {
        case .music: CGSize(width: 356, height: 160)
        case .clipboard: CGSize(width: 360, height: 232)
        case .shelf: CGSize(width: 530, height: 180)
        case .files: CGSize(width: 480, height: 178)
        case .system: CGSize(width: 440, height: 190)
        }
    }

    var isEnabled: Bool {
        let s = Settings.shared
        switch self {
        case .music: return true
        case .clipboard: return s.enableClipboard
        case .shelf: return s.enableShelf
        case .files: return s.enableFiles
        case .system: return s.enableSystem
        }
    }

    static var enabled: [NotchPage] { allCases.filter(\.isEnabled) }
}
