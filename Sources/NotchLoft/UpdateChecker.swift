import AppKit

/// Cherche une version plus récente dans les releases GitHub du dépôt.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle, checking, upToDate, failed
        case available(version: String, url: URL)
    }

    @Published private(set) var state: State = .idle

    private let repo = "ysslgg/NotchLoft"
    private var timer: Timer?

    var currentVersion: String {
        ProcessInfo.processInfo.environment["NOTCHLOFT_FAKE_VERSION"]
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var hasUpdate: Bool {
        if case .available = state { return true }
        return false
    }

    /// Vérifie au lancement puis une fois par jour, si le réglage est actif.
    func startAutomaticChecks() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            if Settings.shared.autoUpdateCheck { self?.check(manual: false) }
        }
        if Settings.shared.autoUpdateCheck { check(manual: false) }
    }

    func check(manual: Bool) {
        if case .checking = state { return }
        state = .checking
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchLoft/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let result = Self.parse(data)
            DispatchQueue.main.async { self?.finish(result, manual: manual) }
        }.resume()
    }

    private struct Release { let version: String; let page: URL; let dmg: URL? }

    private static func parse(_ data: Data?) -> Release? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
            .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page, dmg: dmg)
    }

    private func finish(_ release: Release?, manual: Bool) {
        guard let release else {
            state = .failed
            if manual { alert("Impossible de vérifier les mises à jour", "Vérifie ta connexion Internet et réessaie.") }
            return
        }
        if Self.isNewer(release.version, than: currentVersion) {
            let url = release.dmg ?? release.page
            state = .available(version: release.version, url: url)
            if manual {
                let a = NSAlert()
                a.messageText = "NotchLoft \(release.version) est disponible"
                a.informativeText = "Tu utilises la version \(currentVersion)."
                a.addButton(withTitle: "Télécharger")
                a.addButton(withTitle: "Plus tard")
                NSApp.activate(ignoringOtherApps: true)
                if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
            }
        } else {
            state = .upToDate
            if manual { alert("NotchLoft est à jour", "Tu utilises la dernière version (\(currentVersion)).") }
        }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Comparaison numérique composante par composante : 2.10.0 > 2.9.0.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let y = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
