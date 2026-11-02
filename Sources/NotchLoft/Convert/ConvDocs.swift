import AppKit
import CoreText
import Foundation

// MARK: - Documents (textutil + Core Text)

enum DocConv {
    struct Fmt { let id, label, detail, ext: String; let textutil: String }

    static let formats: [Fmt] = [
        .init(id: "docx", label: "DOCX", detail: "Word", ext: "docx", textutil: "docx"),
        .init(id: "doc", label: "DOC", detail: "Word 97", ext: "doc", textutil: "doc"),
        .init(id: "odt", label: "ODT", detail: "OpenDocument", ext: "odt", textutil: "odt"),
        .init(id: "rtf", label: "RTF", detail: "rich text", ext: "rtf", textutil: "rtf"),
        .init(id: "rtfd", label: "RTFD", detail: "with images", ext: "rtfd", textutil: "rtfd"),
        .init(id: "html", label: "HTML", detail: "web page", ext: "html", textutil: "html"),
        .init(id: "txt", label: "TXT", detail: "plain text", ext: "txt", textutil: "txt"),
        .init(id: "webarchive", label: "WebArchive", detail: "Safari", ext: "webarchive", textutil: "webarchive"),
        .init(id: "wordml", label: "Word XML", detail: "", ext: "xml", textutil: "wordml"),
    ]

    static func targets(for url: URL) -> [ConvTarget] {
        let e = ConvDetect.ext(url)
        let isMD = ["md", "markdown"].contains(e)
        var t: [ConvTarget] = []
        for f in formats {
            if f.ext == e || (f.id == "html" && e == "htm") || (f.id == "txt" && e == "text") { continue }
            if isMD && f.id == "html" { continue }                                   // ajouté ci-dessous (rendu Markdown)
            t.append(ConvTarget(id: "doc.\(f.id)", label: f.label, detail: f.detail, group: "Documents", ext: f.ext) { ctx in
                try await convert(ctx.input, to: ctx.output, textutil: f.textutil)
                return [ctx.output]
            })
        }
        if isMD {
            t.insert(ConvTarget(id: "doc.html", label: "HTML", detail: "rendered Markdown", group: "Documents", ext: "html") { ctx in
                let md = try String(contentsOf: ctx.input, encoding: .utf8)
                try Markdown.html(md, title: ctx.input.deletingPathExtension().lastPathComponent)
                    .write(to: ctx.output, atomically: true, encoding: .utf8)
                return [ctx.output]
            }, at: 0)
        }
        if e != "pdf" {
            t.insert(ConvTarget(id: "doc.pdf", label: "PDF", detail: "text only", group: "Documents", ext: "pdf") { ctx in
                try await pdf(ctx.input, to: ctx.output)
                return [ctx.output]
            }, at: 0)
        }
        return t
    }

    /// Fichier lisible par textutil (le Markdown est d'abord rendu en HTML).
    private static func readable(_ input: URL) throws -> (url: URL, cleanup: URL?) {
        let e = ConvDetect.ext(input)
        guard ["md", "markdown"].contains(e) else { return (input, nil) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notchloft-\(UUID().uuidString).html")
        let md = try String(contentsOf: input, encoding: .utf8)
        try Markdown.html(md, title: input.deletingPathExtension().lastPathComponent).write(to: tmp, atomically: true, encoding: .utf8)
        return (tmp, tmp)
    }

    static func convert(_ input: URL, to out: URL, textutil fmt: String) async throws {
        guard let tu = Shell.tool("textutil") else { throw ConvError.toolMissing("textutil") }
        let src = try readable(input)
        defer { if let c = src.cleanup { try? FileManager.default.removeItem(at: c) } }
        var args = ["-convert", fmt, "-output", out.path]
        if fmt == "txt" { args += ["-encoding", "UTF-8"] }
        try await Shell.check(tu, args + [src.url.path])
    }

    static func pdf(_ input: URL, to out: URL) async throws {
        guard let tu = Shell.tool("textutil") else { throw ConvError.toolMissing("textutil") }
        let src = try readable(input)
        defer { if let c = src.cleanup { try? FileManager.default.removeItem(at: c) } }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notchloft-\(UUID().uuidString).rtf")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await Shell.check(tu, ["-convert", "rtf", "-output", tmp.path, src.url.path])
        guard let attr = NSAttributedString(rtf: try Data(contentsOf: tmp), documentAttributes: nil) else {
            throw ConvError.failed("Couldn't read the document")
        }
        try writePDF(attr, to: out)
    }

    /// Mise en page A4 simple avec Core Text (texte uniquement).
    static func writePDF(_ attr: NSAttributedString, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ConvError.failed("Writing failed") }
        let fs = CTFramesetterCreateWithAttributedString(attr)
        let text = CGRect(x: 56, y: 56, width: 595 - 112, height: 842 - 112)
        var index = 0
        repeat {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: text, transform: nil)
            let frame = CTFramesetterCreateFrame(fs, CFRange(location: index, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if visible.length == 0 { break }
            index += visible.length
        } while index < attr.length
        ctx.closePDF()
    }
}

// MARK: - Markdown → HTML (sous-ensemble courant)

enum Markdown {
    static func html(_ md: String, title: String) -> String {
        var out: [String] = []
        let lines = md.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        var para: [String] = []
        var listKind: String? = nil

        func flushPara() { if !para.isEmpty { out.append("<p>" + inline(para.joined(separator: " ")) + "</p>"); para = [] } }
        func closeList() { if let k = listKind { out.append("</\(k)>"); listKind = nil } }

        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flushPara(); closeList()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                out.append("<pre><code>" + escape(code.joined(separator: "\n")) + "</code></pre>")
            } else if line.isEmpty {
                flushPara(); closeList()
            } else if let m = line.range(of: #"^#{1,6} "#, options: .regularExpression) {
                flushPara(); closeList()
                let level = line[m].count - 1
                out.append("<h\(level)>" + inline(String(line[m.upperBound...])) + "</h\(level)>")
            } else if line.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil {
                flushPara(); closeList(); out.append("<hr>")
            } else if line.hasPrefix(">") {
                flushPara(); closeList()
                out.append("<blockquote>" + inline(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)) + "</blockquote>")
            } else if let m = line.range(of: #"^[-*+] "#, options: .regularExpression) {
                flushPara()
                if listKind != "ul" { closeList(); out.append("<ul>"); listKind = "ul" }
                out.append("<li>" + inline(String(line[m.upperBound...])) + "</li>")
            } else if let m = line.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                flushPara()
                if listKind != "ol" { closeList(); out.append("<ol>"); listKind = "ol" }
                out.append("<li>" + inline(String(line[m.upperBound...])) + "</li>")
            } else {
                closeList()
                para.append(line)
            }
            i += 1
        }
        flushPara(); closeList()
        return "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>\(escape(title))</title>"
            + "<style>body{font-family:-apple-system,Helvetica,sans-serif;max-width:46em;margin:2em auto;line-height:1.5;padding:0 1em}"
            + "code{background:#f2f2f2;padding:.1em .3em;border-radius:3px}pre{background:#f2f2f2;padding:1em;overflow:auto}"
            + "blockquote{border-left:4px solid #ccc;margin-left:0;padding-left:1em;color:#555}</style></head><body>\n"
            + out.joined(separator: "\n") + "\n</body></html>\n"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func inline(_ s: String) -> String {
        var t = escape(s)
        func sub(_ pattern: String, _ template: String) {
            t = t.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        sub(#"`([^`]+)`"#, "<code>$1</code>")
        sub(#"\*\*([^*]+)\*\*"#, "<strong>$1</strong>")
        sub(#"__([^_]+)__"#, "<strong>$1</strong>")
        sub(#"\*([^*]+)\*"#, "<em>$1</em>")
        sub(#"(?<![\w])_([^_]+)_(?![\w])"#, "<em>$1</em>")
        sub(#"~~([^~]+)~~"#, "<del>$1</del>")
        sub(#"!\[([^\]]*)\]\(([^)\s]+)\)"#, "<img alt=\"$1\" src=\"$2\">")
        sub(#"\[([^\]]+)\]\(([^)\s]+)\)"#, "<a href=\"$2\">$1</a>")
        return t
    }
}
