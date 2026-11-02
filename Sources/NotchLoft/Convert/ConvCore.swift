import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Types

enum FileCategory: String {
    case image, video, audio, pdf, document, data, archive, folder, other
}

enum ConvError: Error {
    case unsupported
    case toolMissing(String)
    case failed(String)
    case cancelled
}

/// Contexte d'une conversion : fichiers d'entrée, destination déjà choisie (jamais écrasée) et progression.
struct ConvContext: @unchecked Sendable {
    let inputs: [URL]
    let output: URL
    let progress: @Sendable (Double) -> Void
    var input: URL { inputs[0] }
}

/// Un format de sortie proposé pour un fichier.
struct ConvTarget: Identifiable, Hashable, @unchecked Sendable {
    enum Mode { case each, merge }
    let id: String
    let label: String          // « PNG », « MP4 · 1080p »…
    let detail: String         // précision courte (« sans perte », « petit fichier »…)
    let group: String          // clé anglaise du groupe (« Images », « Audio »…)
    let ext: String            // extension de sortie ; vide pour un dossier
    var mode: Mode = .each
    var isFolder = false
    let run: @Sendable (ConvContext) async throws -> [URL]

    static func == (a: ConvTarget, b: ConvTarget) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Détection

enum ConvDetect {
    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "jpe", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp", "jp2",
                                         "j2k", "ico", "icns", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "pef", "srw",
                                         "tga", "psd", "hdr", "exr", "avif"]
    static let avVideoExts: Set<String> = ["mov", "mp4", "m4v", "3gp", "3g2"]
    static let otherVideoExts: Set<String> = ["mkv", "avi", "webm", "flv", "wmv", "mpg", "mpeg", "ts", "m2ts", "vob", "ogv", "mxf", "f4v"]
    static let avAudioExts: Set<String> = ["m4a", "mp3", "aac", "wav", "wave", "aif", "aiff", "aifc", "caf", "flac", "mp2", "ac3", "amr", "m4r", "alac"]
    static let otherAudioExts: Set<String> = ["ogg", "oga", "opus", "wma", "mka", "ape", "wv", "dsf"]
    static let docExts: Set<String> = ["txt", "text", "rtf", "rtfd", "html", "htm", "doc", "docx", "odt", "wordml", "webarchive", "md", "markdown"]
    static let dataExts: Set<String> = ["json", "plist", "csv", "tsv"]
    static let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "7z", "rar", "cpio", "iso", "cab", "lzma", "z"]

    static func ext(_ url: URL) -> String {
        let n = url.lastPathComponent.lowercased()
        for double in ["tar.gz", "tar.bz2", "tar.xz", "tar.lzma", "tar.z"] where n.hasSuffix("." + double) {
            return double
        }
        return url.pathExtension.lowercased()
    }

    static func category(_ url: URL) -> FileCategory {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
           url.pathExtension.lowercased() != "rtfd" { return .folder }
        let e = ext(url)
        if e == "pdf" { return .pdf }
        if imageExts.contains(e) { return .image }
        if avVideoExts.contains(e) || otherVideoExts.contains(e) { return .video }
        if avAudioExts.contains(e) || otherAudioExts.contains(e) { return .audio }
        if docExts.contains(e) { return .document }
        if dataExts.contains(e) { return .data }
        if archiveExts.contains(e) || e.hasPrefix("tar.") { return .archive }
        return .other
    }

    /// Nom lisible du type (« PNG image », « Dossier »…) — la partie langue est ajoutée par l'interface.
    static func typeName(_ url: URL) -> String {
        let e = ext(url)
        switch category(url) {
        case .folder: return "Folder"
        case .other: return e.isEmpty ? "File" : e.uppercased()
        default: return e.uppercased()
        }
    }
}

// MARK: - Noms de sortie

enum ConvNaming {
    /// Dossier de sortie : à côté du fichier d'origine, sinon dans Téléchargements.
    static func directory(for input: URL) -> URL {
        let dir = input.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: dir.path) { return dir }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// Dossier libre : « rapport pages », puis « rapport pages 2 »…
    static func freeFolder(named name: String, in dir: URL) -> URL {
        var n = 1
        func make(_ n: Int) -> URL { dir.appendingPathComponent(n == 1 ? name : "\(name) \(n)", isDirectory: true) }
        while FileManager.default.fileExists(atPath: make(n).path) { n += 1 }
        return make(n)
    }

    /// Chemin libre : « photo.png », puis « photo 2.png », « photo 3.png »…
    static func destination(for input: URL, ext: String, isFolder: Bool = false, suffix: String = "") -> URL {
        let dir = directory(for: input)
        var base = input.deletingPathExtension().lastPathComponent
        let inExt = ConvDetect.ext(input)
        if input.pathExtension.lowercased() == "rtfd" || ConvDetect.category(input) == .folder { base = input.lastPathComponent }
        if ConvDetect.ext(input).hasPrefix("tar."), base.lowercased().hasSuffix(".tar") { base = String(base.dropLast(4)) }
        base += suffix
        if !isFolder, suffix.isEmpty, inExt == ext.lowercased() { base += " (converted)" }
        func make(_ n: Int) -> URL {
            let name = n == 1 ? base : "\(base) \(n)"
            return isFolder || ext.isEmpty ? dir.appendingPathComponent(name, isDirectory: true)
                                           : dir.appendingPathComponent(name).appendingPathExtension(ext)
        }
        var n = 1
        while FileManager.default.fileExists(atPath: make(n).path) { n += 1 }
        return make(n)
    }
}

// MARK: - Outils système

enum Shell {
    struct Result { let status: Int32; let out: String; let err: String }

    /// Lance un programme sans bloquer, en le coupant si la tâche est annulée.
    static func run(_ exe: String, _ args: [String], env: [String: String] = [:], cwd: URL? = nil) async throws -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if !env.isEmpty { p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }
        p.currentDirectoryURL = cwd
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        let box = DataBox()
        outPipe.fileHandleForReading.readabilityHandler = { h in box.appendOut(h.availableData) }
        errPipe.fileHandleForReading.readabilityHandler = { h in box.appendErr(h.availableData) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Result, Error>) in
                p.terminationHandler = { proc in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    box.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
                    box.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
                    c.resume(returning: Result(status: proc.terminationStatus, out: box.out, err: box.err))
                }
                do { try p.run() } catch { c.resume(throwing: ConvError.toolMissing(exe)) }
            }
        } onCancel: {
            if p.isRunning { p.terminate() }
        }
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var o = Data(), e = Data()
        func appendOut(_ d: Data) { lock.lock(); o.append(d); lock.unlock() }
        func appendErr(_ d: Data) { lock.lock(); e.append(d.suffix(20_000)); lock.unlock() }
        var out: String { lock.lock(); defer { lock.unlock() }; return String(decoding: o, as: UTF8.self) }
        var err: String { lock.lock(); defer { lock.unlock() }; return String(decoding: e, as: UTF8.self) }
    }

    /// Lance et exige un code de sortie 0.
    @discardableResult
    static func check(_ exe: String, _ args: [String], env: [String: String] = [:], cwd: URL? = nil) async throws -> Result {
        let r = try await run(exe, args, env: env, cwd: cwd)
        if Task.isCancelled { throw ConvError.cancelled }
        guard r.status == 0 else {
            let msg = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConvError.failed(msg.isEmpty ? "\((exe as NSString).lastPathComponent) exited with code \(r.status)" : String(msg.suffix(300)))
        }
        return r
    }

    static func tool(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/opt/local/bin", "/bin"] {
            let p = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}

// MARK: - Registre

enum ConvEngine {
    /// Formats proposés pour un fichier.
    static func targets(for url: URL) -> [ConvTarget] {
        switch ConvDetect.category(url) {
        case .image: return ImageConv.targets(for: url) + FFmpegConv.targets(for: url, category: .image) + commonExtras(url)
        case .pdf: return PDFConv.targets(for: url) + commonExtras(url)
        case .audio: return AudioConv.targets(for: url) + FFmpegConv.targets(for: url, category: .audio) + commonExtras(url)
        case .video: return VideoConv.targets(for: url) + FFmpegConv.targets(for: url, category: .video) + commonExtras(url)
        case .document: return DocConv.targets(for: url) + commonExtras(url)
        case .data: return DataConv.targets(for: url) + commonExtras(url)
        case .archive: return ArchiveConv.targets(for: url) + commonExtras(url)
        case .folder: return ArchiveConv.targets(for: url)
        case .other: return commonExtras(url)
        }
    }

    private static func commonExtras(_ url: URL) -> [ConvTarget] {
        let cat = ConvDetect.category(url)
        // Une archive se convertit en archive ; pour les autres fichiers, on propose aussi de les compresser.
        var t: [ConvTarget] = cat == .archive ? [] : ArchiveConv.targets(for: url)
        t.append(Base64Conv.encodeTarget)
        if ["b64", "base64"].contains(ConvDetect.ext(url)) { t.insert(Base64Conv.decodeTarget, at: 0) }
        return t
    }

    /// Formats communs à tous les fichiers (lot), plus la fusion de plusieurs images en un seul PDF.
    static func targets(for urls: [URL]) -> [ConvTarget] {
        guard let first = urls.first else { return [] }
        if urls.count == 1 { return targets(for: first) }
        var common = targets(for: first).filter { $0.mode == .each }
        for u in urls.dropFirst() {
            let ids = Set(targets(for: u).map(\.id))
            common = common.filter { ids.contains($0.id) }
        }
        if urls.allSatisfy({ ConvDetect.category($0) == .image }) { common.insert(ImageConv.mergePDF, at: 0) }
        if urls.allSatisfy({ ConvDetect.category($0) == .pdf }) { common.insert(PDFConv.mergeTarget, at: 0) }
        return common
    }

    /// Exécute une cible sur une liste de fichiers ; renvoie tous les fichiers créés.
    static func convert(_ urls: [URL], with target: ConvTarget,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        var made: [URL] = []
        if target.mode == .merge {
            let out = ConvNaming.destination(for: urls[0], ext: target.ext, suffix: " (merged)")
            made += try await target.run(ConvContext(inputs: urls, output: out, progress: progress))
            return made
        }
        for (i, url) in urls.enumerated() {
            try Task.checkCancellation()
            let out = ConvNaming.destination(for: url, ext: target.ext, isFolder: target.isFolder)
            let share = 1.0 / Double(urls.count)
            let base = Double(i) * share
            made += try await target.run(ConvContext(inputs: [url], output: out, progress: { p in
                progress(base + max(0, min(1, p)) * share)
            }))
            progress(Double(i + 1) * share)
        }
        return made
    }
}
