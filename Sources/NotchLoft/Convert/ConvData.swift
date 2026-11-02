import Foundation

// MARK: - Données structurées (JSON, plist, CSV, TSV)

enum DataConv {
    static func targets(for url: URL) -> [ConvTarget] {
        let e = ConvDetect.ext(url)
        func t(_ id: String, _ label: String, _ detail: String, _ ext: String,
               _ work: @escaping @Sendable (URL, URL) throws -> Void) -> ConvTarget {
            ConvTarget(id: "data.\(id)", label: label, detail: detail, group: "Data", ext: ext) { ctx in
                try work(ctx.input, ctx.output)
                return [ctx.output]
            }
        }
        switch e {
        case "json":
            return [
                t("plist", "Plist", "XML", "plist") { try writePlist(try readJSON($0), $1, format: .xml) },
                t("plist-bin", "Plist", "binary", "plist") { try writePlist(try readJSON($0), $1, format: .binary) },
                t("csv", "CSV", "table", "csv") { try table(try readJSON($0), sep: ",").write(to: $1, atomically: true, encoding: .utf8) },
                t("tsv", "TSV", "table", "tsv") { try table(try readJSON($0), sep: "\t").write(to: $1, atomically: true, encoding: .utf8) },
                t("yaml", "YAML", "", "yaml") { try (YAML.emit(try readJSON($0)) + "\n").write(to: $1, atomically: true, encoding: .utf8) },
                t("md", "Markdown", "table", "md") { try markdownTable(try readJSON($0)).write(to: $1, atomically: true, encoding: .utf8) },
                t("json-min", "JSON · minified", "", "json") { try writeJSON(try readJSON($0), $1, pretty: false) },
                t("json-pretty", "JSON · formatted", "sorted keys", "json") { try writeJSON(try readJSON($0), $1, pretty: true) },
            ]
        case "plist":
            return [
                t("json", "JSON", "", "json") { try writeJSON(try readPlist($0), $1, pretty: true) },
                t("plist-xml", "Plist", "XML", "plist") { try writePlist(try readPlist($0), $1, format: .xml) },
                t("plist-bin", "Plist", "binary", "plist") { try writePlist(try readPlist($0), $1, format: .binary) },
                t("yaml", "YAML", "", "yaml") { try (YAML.emit(try readPlist($0)) + "\n").write(to: $1, atomically: true, encoding: .utf8) },
            ]
        case "csv", "tsv":
            let sep: Character = e == "csv" ? "," : "\t"
            var out = [
                t("json", "JSON", "array of objects", "json") { try writeJSON(try readTable($0, sep: sep), $1, pretty: true) },
                t("md", "Markdown", "table", "md") { try markdownTable(try readTable($0, sep: sep)).write(to: $1, atomically: true, encoding: .utf8) },
                t("html", "HTML", "table", "html") { try htmlTable(try readTable($0, sep: sep)).write(to: $1, atomically: true, encoding: .utf8) },
                t("yaml", "YAML", "", "yaml") { try (YAML.emit(try readTable($0, sep: sep)) + "\n").write(to: $1, atomically: true, encoding: .utf8) },
                t("plist", "Plist", "XML", "plist") { try writePlist(try readTable($0, sep: sep), $1, format: .xml) },
            ]
            let (otherId, otherLabel, otherExt, otherSep): (String, String, String, String) =
                e == "csv" ? ("tsv", "TSV", "tsv", "\t") : ("csv", "CSV", "csv", ",")
            out.insert(t(otherId, otherLabel, "re-separated", otherExt) { src, dst in
                try table(try readTable(src, sep: sep), sep: otherSep).write(to: dst, atomically: true, encoding: .utf8)
            }, at: 0)
            return out
        default: return []
        }
    }

    // MARK: Lecture / écriture

    static func readJSON(_ u: URL) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: Data(contentsOf: u), options: [.fragmentsAllowed]) }
        catch { throw ConvError.failed("Invalid JSON") }
    }

    static func readPlist(_ u: URL) throws -> Any {
        do { return try PropertyListSerialization.propertyList(from: Data(contentsOf: u), options: [], format: nil) }
        catch { throw ConvError.failed("Invalid plist") }
    }

    /// Les dates et données d'une plist n'existent pas en JSON : on les convertit en texte.
    static func jsonSafe(_ v: Any) -> Any {
        switch v {
        case let d as [String: Any]: return d.mapValues(jsonSafe)
        case let a as [Any]: return a.map(jsonSafe)
        case let d as Date: return ISO8601DateFormatter().string(from: d)
        case let d as Data: return d.base64EncodedString()
        default: return v
        }
    }

    static func writeJSON(_ v: Any, _ out: URL, pretty: Bool) throws {
        let safe = jsonSafe(v)
        guard JSONSerialization.isValidJSONObject(safe) || !(safe is [Any] || safe is [String: Any]) else { throw ConvError.failed("Invalid data") }
        var opts: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes]
        if pretty { opts.formUnion([.prettyPrinted, .sortedKeys]) }
        try JSONSerialization.data(withJSONObject: safe, options: opts).write(to: out)
    }

    static func writePlist(_ v: Any, _ out: URL, format: PropertyListSerialization.PropertyListFormat) throws {
        let data: Data
        do { data = try PropertyListSerialization.data(fromPropertyList: v, format: format, options: 0) }
        catch { throw ConvError.failed("This data can't be stored in a plist (null values aren't allowed)") }
        try data.write(to: out)
    }

    // MARK: CSV

    static func parseCSV(_ text: String, sep: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == sep { row.append(field); field = "" }
            else if c == "\n" { row.append(field); rows.append(row); row = []; field = "" }
            else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    static func infer(_ s: String) -> Any {
        if s.isEmpty { return "" }
        if s == "true" { return true }
        if s == "false" { return false }
        if s == "null" { return NSNull() }
        if s.range(of: #"^-?(0|[1-9]\d*)$"#, options: .regularExpression) != nil, let n = Int(s) { return n }
        if s.range(of: #"^-?(0|[1-9]\d*)\.\d+$"#, options: .regularExpression) != nil, let d = Double(s) { return d }
        return s
    }

    static func readTable(_ u: URL, sep: Character) throws -> Any {
        guard let text = (try? String(contentsOf: u, encoding: .utf8)) ?? (try? String(contentsOf: u, encoding: .isoLatin1)) else {
            throw ConvError.failed("Unreadable file")
        }
        let rows = parseCSV(text, sep: sep)
        guard let head = rows.first else { throw ConvError.failed("Empty file") }
        return rows.dropFirst().map { r in
            var d: [String: Any] = [:]
            for (i, h) in head.enumerated() { d[h.isEmpty ? "column\(i + 1)" : h] = i < r.count ? infer(r[i]) : NSNull() }
            return d
        }
    }

    static func cell(_ v: Any?) -> String {
        switch v {
        case nil, is NSNull: return ""
        case let s as String: return s
        case let n as NSNumber: return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
        default:
            if let v, JSONSerialization.isValidJSONObject(v), let d = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]) {
                return String(decoding: d, as: UTF8.self)
            }
            return "\(v!)"
        }
    }

    /// Lignes d'un tableau JSON : liste d'objets (colonnes = union des clés) ou liste de listes.
    static func rows(_ v: Any) throws -> [[String]] {
        let value = jsonSafe(v)
        if let arr = value as? [[String: Any]] {
            var keys: [String] = []
            for o in arr { for k in o.keys.sorted() where !keys.contains(k) { keys.append(k) } }
            return [keys] + arr.map { o in keys.map { cell(o[$0]) } }
        }
        if let arr = value as? [[Any]] { return arr.map { $0.map { cell($0) } } }
        if let o = value as? [String: Any] { let keys = o.keys.sorted(); return [keys, keys.map { cell(o[$0]) }] }
        throw ConvError.failed("Needs a list of objects or rows")
    }

    static func table(_ v: Any, sep: String) throws -> String {
        func esc(_ s: String) -> String {
            s.contains(sep) || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        return try rows(v).map { $0.map(esc).joined(separator: sep) }.joined(separator: "\n") + "\n"
    }

    static func markdownTable(_ v: Any) throws -> String {
        let r = try rows(v)
        guard let head = r.first else { return "" }
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
        var out = "| " + head.map(esc).joined(separator: " | ") + " |\n"
        out += "|" + head.map { _ in " --- |" }.joined() + "\n"
        for row in r.dropFirst() { out += "| " + row.map(esc).joined(separator: " | ") + " |\n" }
        return out
    }

    static func htmlTable(_ v: Any) throws -> String {
        let r = try rows(v)
        guard let head = r.first else { return "" }
        var out = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><style>table{border-collapse:collapse;font-family:sans-serif}"
            + "td,th{border:1px solid #ccc;padding:4px 8px}th{background:#f2f2f2}</style></head><body>\n<table>\n<tr>"
        out += head.map { "<th>\(Markdown.escape($0))</th>" }.joined() + "</tr>\n"
        for row in r.dropFirst() { out += "<tr>" + row.map { "<td>\(Markdown.escape($0))</td>" }.joined() + "</tr>\n" }
        return out + "</table>\n</body></html>\n"
    }
}

// MARK: - YAML (écriture seule)

enum YAML {
    static func emit(_ v: Any, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch DataConv.jsonSafe(v) {
        case let d as [String: Any]:
            if d.isEmpty { return "{}" }
            return d.keys.sorted().map { k -> String in
                let val = d[k]!
                let key = scalarKey(k)
                if let a = val as? [Any], !a.isEmpty { return "\(pad)\(key):\n" + emit(a, indent: indent + 1) }
                if let o = val as? [String: Any], !o.isEmpty { return "\(pad)\(key):\n" + emit(o, indent: indent + 1) }
                return "\(pad)\(key): \(scalar(val))"
            }.joined(separator: "\n")
        case let a as [Any]:
            if a.isEmpty { return "[]" }
            return a.map { item -> String in
                if let o = item as? [String: Any], !o.isEmpty {
                    let body = emit(o, indent: indent + 1).split(separator: "\n", omittingEmptySubsequences: false)
                    return "\(pad)- " + body.enumerated().map { $0.offset == 0 ? String($0.element).trimmingCharacters(in: .whitespaces) : String($0.element) }
                        .joined(separator: "\n")
                }
                if let l = item as? [Any], !l.isEmpty { return "\(pad)-\n" + emit(l, indent: indent + 1) }
                return "\(pad)- \(scalar(item))"
            }.joined(separator: "\n")
        case let other: return scalar(other)
        }
    }

    static func scalarKey(_ k: String) -> String {
        k.range(of: #"^[A-Za-z_][A-Za-z0-9_\-]*$"#, options: .regularExpression) != nil ? k : quote(k)
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    static func scalar(_ v: Any) -> String {
        switch v {
        case is NSNull: return "null"
        case let n as NSNumber: return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
        case let s as String:
            let plain = s.range(of: #"^[A-Za-z][A-Za-z0-9 _\-\.]*$"#, options: .regularExpression) != nil
            let reserved = ["true", "false", "null", "yes", "no", "on", "off", "~"].contains(s.lowercased())
            return plain && !reserved ? s : quote(s)
        case let a as [Any]: return a.isEmpty ? "[]" : quote("\(a)")
        case let d as [String: Any]: return d.isEmpty ? "{}" : quote("\(d)")
        default: return quote("\(v)")
        }
    }
}

// MARK: - Base64

enum Base64Conv {
    static let encodeTarget = ConvTarget(id: "base64.encode", label: "Base64", detail: "text", group: "Text", ext: "b64") { ctx in
        let d = try Data(contentsOf: ctx.input)
        try d.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed]).write(to: ctx.output, atomically: true, encoding: .utf8)
        return [ctx.output]
    }

    static let decodeTarget = ConvTarget(id: "base64.decode", label: "Decode Base64", detail: "to the original file", group: "Text", ext: "bin") { ctx in
        let s = try String(contentsOf: ctx.input, encoding: .utf8)
        guard let d = Data(base64Encoded: s, options: .ignoreUnknownCharacters) else { throw ConvError.failed("Not valid Base64") }
        try d.write(to: ctx.output)
        return [ctx.output]
    }
}

// MARK: - Archives

enum ArchiveConv {
    static let tarExts: Set<String> = ["tar", "tar.gz", "tgz", "tar.bz2", "tbz", "tbz2", "tar.xz", "txz", "tar.lzma", "tar.z"]

    static func targets(for url: URL) -> [ConvTarget] {
        let e = ConvDetect.ext(url)
        let cat = ConvDetect.category(url)
        var t: [ConvTarget] = []
        let isArchive = cat == .archive
        if isArchive {
            t.append(ConvTarget(id: "archive.extract", label: "Extract", detail: "to a folder", group: "Archives", ext: "", isFolder: true) { ctx in
                try await extract(ctx.input, to: ctx.output)
                return [ctx.output]
            })
        }
        if e != "zip" {
            t.append(ConvTarget(id: "archive.zip", label: "ZIP", detail: "", group: "Archives", ext: "zip") { ctx in
                try await pack(ctx.input, to: ctx.output, kind: .zip)
                return [ctx.output]
            })
        }
        if !(e == "tar.gz" || e == "tgz") {
            t.append(ConvTarget(id: "archive.targz", label: "TAR.GZ", detail: "", group: "Archives", ext: "tar.gz") { ctx in
                try await pack(ctx.input, to: ctx.output, kind: .tarGz)
                return [ctx.output]
            })
        }
        if !(e == "tar.bz2" || e == "tbz2" || e == "tbz") {
            t.append(ConvTarget(id: "archive.tarbz2", label: "TAR.BZ2", detail: "", group: "Archives", ext: "tar.bz2") { ctx in
                try await pack(ctx.input, to: ctx.output, kind: .tarBz2)
                return [ctx.output]
            })
        }
        if e != "tar" {
            t.append(ConvTarget(id: "archive.tar", label: "TAR", detail: "no compression", group: "Archives", ext: "tar") { ctx in
                try await pack(ctx.input, to: ctx.output, kind: .tar)
                return [ctx.output]
            })
        }
        return t
    }

    enum Kind { case zip, tar, tarGz, tarBz2 }

    /// Extrait n'importe quelle archive prise en charge par macOS (zip, tar.*, 7z, rar, gz, bz2, xz…).
    static func extract(_ input: URL, to folder: URL) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let e = ConvDetect.ext(input)
        do {
            if e == "zip" {
                try await Shell.check("/usr/bin/ditto", ["-x", "-k", input.path, folder.path])
            } else if let tool = ["gz": "gzip", "bz2": "bzip2", "xz": "xz", "lzma": "xz", "z": "gzip"][e] {
                // Fichier unique compressé : on le décompresse sous son nom sans l'extension.
                guard let exe = Shell.tool(tool) else { throw ConvError.toolMissing(tool) }
                let dest = folder.appendingPathComponent(input.deletingPathExtension().lastPathComponent)
                try await Shell.check("/bin/sh", ["-c", "\"$0\" -dc \"$1\" > \"$2\"", exe, input.path, dest.path])
            } else {
                try await Shell.check("/usr/bin/tar", ["-xf", input.path, "-C", folder.path])
            }
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
        try? fm.removeItem(at: folder.appendingPathComponent("__MACOSX"))
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        if items.isEmpty { try? fm.removeItem(at: folder); throw ConvError.failed("The archive is empty or unsupported") }
    }

    static func pack(_ input: URL, to out: URL, kind: Kind) async throws {
        var source = input
        var cleanup: URL?
        // Une archive est d'abord extraite, puis recompressée dans l'autre format.
        if ConvDetect.category(input) == .archive {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notchloft-\(UUID().uuidString)", isDirectory: true)
            try await extract(input, to: tmp)
            source = tmp
            cleanup = tmp
        }
        defer { if let c = cleanup { try? FileManager.default.removeItem(at: c) } }
        let dir = source.deletingLastPathComponent(), name = source.lastPathComponent
        switch kind {
        case .zip:
            if cleanup != nil {
                try await Shell.check("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", source.path, out.path])
            } else {
                try await Shell.check("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, out.path])
            }
        case .tar, .tarGz, .tarBz2:
            let flag = kind == .tar ? "-cf" : (kind == .tarGz ? "-czf" : "-cjf")
            let args = cleanup != nil ? [flag, out.path, "-C", source.path, "."] : [flag, out.path, "-C", dir.path, name]
            try await Shell.check("/usr/bin/tar", args, env: ["COPYFILE_DISABLE": "1"])
        }
    }
}
