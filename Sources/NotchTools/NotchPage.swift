import SwiftUI

/// Pages de l'encoche : la musique et les outils.
enum NotchPage: String, CaseIterable, Identifiable {
    case music, clipboard, shelf, audio

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "photo.on.rectangle.angled"
        case .audio: "slider.vertical.3"
        }
    }

    var title: String {
        switch self {
        case .music: "Musique"
        case .clipboard: "Presse-papier"
        case .shelf: "Étendoir"
        case .audio: "Audio"
        }
    }

    /// Taille de l'encoche ouverte sur cette page.
    var size: CGSize {
        switch self {
        case .music: CGSize(width: 356, height: 160)
        case .clipboard: CGSize(width: 360, height: 232)
        case .shelf: CGSize(width: 430, height: 160)
        case .audio: CGSize(width: 340, height: 184)
        }
    }

    var isEnabled: Bool {
        let s = Settings.shared
        switch self {
        case .music: return true
        case .clipboard: return s.enableClipboard
        case .shelf: return s.enableShelf
        case .audio: return s.enableAudio
        }
    }

    static var enabled: [NotchPage] { allCases.filter(\.isEnabled) }
}
