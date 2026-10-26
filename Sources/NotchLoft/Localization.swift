import Foundation

/// Langues de l'interface : anglais par défaut, français en option (réglage dans le menu ♪).
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, fr
    var id: String { rawValue }
    var label: String {
        switch self {
        case .en: "English"
        case .fr: "Français"
        }
    }
}

/// Traduit un texte écrit en anglais vers la langue choisie ; `args` remplit les %@, %d, %.1f…
func tr(_ english: String, _ args: CVarArg...) -> String {
    let lang = Settings.shared.language
    let format = lang == .fr ? (Localization.fr[english] ?? english) : english
    guard !args.isEmpty else { return format }
    return String(format: format, locale: Locale(identifier: lang.rawValue), arguments: args)
}

enum Localization {
    static let fr: [String: String] = [
        "%.0f GB": "%.0f Go",
        "%.0f GB free": "%.0f Go libres",
        "%.1f / %.0f GB": "%.1f / %.0f Go",
        "%.1f of %.0f GB used": "%.1f sur %.0f Go utilisés",
        "%@ left": "%@ restantes",
        "%@ until full": "%@ avant 100 %%",
        "%d cycles": "%d cycles",
        "%d h %02d": "%d h %02d",
        "%d items · drag them anywhere": "%d éléments · glisse-les où tu veux",
        "%d min": "%d min",
        "1 item · drag it anywhere": "1 élément · glisse-le où tu veux",
        "15 seconds": "15 secondes",
        "45 seconds": "45 secondes",
        "Accent color": "Couleur d'accent",
        "Allow access to the screenshots folder (System Settings → Privacy & Security).": "Autorise l'accès au dossier des captures (Réglages Système → Confidentialité).",
        "Animate new screenshots": "Animer l'arrivée des captures",
        "Animated visualizer": "Visualiseur animé",
        "Appearance & music": "Apparence et musique",
        "Battery": "Batterie",
        "Battery & system": "Batterie et système",
        "Behavior": "Comportement",
        "Blue": "Bleu",
        "Blurred artwork background": "Fond flou de la pochette",
        "CPU": "Processeur",
        "CPU · load": "Processeur · charge",
        "Charged · plugged in": "Chargée · branchée",
        "Charging": "En charge",
        "Check automatically": "Vérifier automatiquement",
        "Check for updates…": "Rechercher des mises à jour…",
        "Check your Internet connection and try again.": "Vérifie ta connexion Internet et réessaie.",
        "Checking…": "Recherche en cours…",
        "Clear": "Effacer",
        "Clear clipboard history": "Vider le presse-papier",
        "Click: open · Drag: drop elsewhere": "Clic : ouvrir · Glisser : déposer ailleurs",
        "Clipboard": "Presse-papier",
        "Copied ✓": "Copié ✓",
        "Copy image": "Copier l'image",
        "Copy path": "Copier le chemin",
        "Copy some text and it will show up here.": "Copie du texte : il apparaîtra ici.",
        "Couldn't check for updates": "Impossible de vérifier les mises à jour",
        "Critical": "Critique",
        "Disk": "Disque",
        "Download": "Télécharger",
        "Drop files or folders here": "Glisse des fichiers ou des dossiers ici",
        "Fair": "Moyenne",
        "Featured system info": "Info système en grand",
        "File tray": "Dépôt de fichiers",
        "From artwork": "Selon la pochette",
        "Green": "Vert",
        "Haptic feedback": "Retour haptique",
        "Health %d%%": "Santé %d %%",
        "Hide after a pause": "Masquer après une pause",
        "Hide in full-screen apps": "Se masquer dans les apps en plein écran",
        "Idle width": "Largeur au repos",
        "Language": "Langue",
        "Last used": "Dernière utilisée",
        "Later": "Plus tard",
        "Launch at login": "Lancer au démarrage",
        "Memory": "Mémoire",
        "Move to Trash": "Mettre à la corbeille",
        "Music": "Musique",
        "Narrow": "Étroite",
        "Never": "Jamais",
        "Normal": "Normale",
        "NotchLoft %@ is available": "NotchLoft %@ est disponible",
        "NotchLoft is up to date": "NotchLoft est à jour",
        "Nothing is playing": "Aucune lecture en cours",
        "On battery": "Sur batterie",
        "Open app": "Ouvrir l'app",
        "Open tools when nothing is playing": "Ouvrir les outils quand rien ne joue",
        "Opening & display": "Ouverture et affichage",
        "Page on open": "Page à l'ouverture",
        "Pink": "Rose",
        "Plugged in": "Branchée",
        "Progress ring": "Bague de progression",
        "Quit NotchLoft": "Quitter NotchLoft",
        "Remove all": "Tout retirer",
        "Remove from shelf": "Retirer de l'étendoir",
        "Remove from tray": "Retirer du dépôt",
        "Remove from tray (the file stays untouched)": "Retirer du dépôt (le fichier reste intact)",
        "Retry access to the screenshots folder": "Réessayer l'accès au dossier des captures",
        "Screenshot shelf": "Étendoir à captures",
        "Serious": "Élevée",
        "Shelf": "Étendoir",
        "Show in Finder": "Afficher dans le Finder",
        "Show “%@” in large": "Afficher « %@ » en grand",
        "Sound-reactive visualizer (permission required)": "Visualiseur réactif au son (autorisation requise)",
        "Thermal pressure: %@": "Pression thermique : %@",
        "They stay hanging until you take them back.": "Ils restent accrochés jusqu'à ce que tu les reprennes.",
        "Tools": "Outils",
        "Version %@": "Version %@",
        "White": "Blanc",
        "Wide": "Large",
        "You are using the latest version (%@).": "Tu utilises la dernière version (%@).",
        "You are using version %@.": "Tu utilises la version %@.",
        "Your latest screenshots hang here.": "Tes dernières captures d'écran s'accrochent ici.",
        "free of %.0f GB · %.0f%% used": "libres sur %.0f Go · %.0f %% utilisé",
        "⬆︎ Download version %@": "⬆︎ Télécharger la version %@",
    ]
}
