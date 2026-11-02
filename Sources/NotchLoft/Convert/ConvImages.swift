import AppKit
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

// MARK: - Images

enum ImageConv {
    struct Format {
        let id: String, label: String, detail: String, ext: String
        let type: String        // identifiant UTI pour ImageIO
        var quality: Double? = nil
        var flatten = false      // pas de transparence (JPEG, BMP)
        var maxSide: Int? = nil  // ICO : 256 px au plus
    }

    static let formats: [Format] = [
        .init(id: "png", label: "PNG", detail: "lossless", ext: "png", type: "public.png"),
        .init(id: "jpeg", label: "JPEG", detail: "high quality", ext: "jpg", type: "public.jpeg", quality: 0.92, flatten: true),
        .init(id: "jpeg-small", label: "JPEG · small", detail: "small file", ext: "jpg", type: "public.jpeg", quality: 0.6, flatten: true),
        .init(id: "heic", label: "HEIC", detail: "compact", ext: "heic", type: "public.heic", quality: 0.85),
        .init(id: "tiff", label: "TIFF", detail: "lossless", ext: "tiff", type: "public.tiff"),
        .init(id: "gif", label: "GIF", detail: "256 colors", ext: "gif", type: "com.compuserve.gif"),
        .init(id: "bmp", label: "BMP", detail: "uncompressed", ext: "bmp", type: "com.microsoft.bmp", flatten: true),
        .init(id: "jp2", label: "JPEG 2000", detail: "", ext: "jp2", type: "public.jpeg-2000", quality: 0.85),
        .init(id: "webp", label: "WebP", detail: "web", ext: "webp", type: "org.webmproject.webp", quality: 0.85),
        .init(id: "avif", label: "AVIF", detail: "web", ext: "avif", type: "public.avif", quality: 0.8),
        .init(id: "ico", label: "ICO", detail: "Windows icon", ext: "ico", type: "com.microsoft.ico", maxSide: 256),
        .init(id: "icns", label: "ICNS", detail: "macOS icon", ext: "icns", type: "com.apple.icns", maxSide: 512),
    ]

    static let writable: Set<String> = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    static func targets(for url: URL) -> [ConvTarget] {
        let e = ConvDetect.ext(url)
        var out: [ConvTarget] = []
        for f in formats where writable.contains(f.type) {
            let same = (f.ext == e) || (f.ext == "jpg" && ["jpeg", "jpe"].contains(e)) || (f.ext == "tiff" && e == "tif")
            if same && f.id != "jpeg-small" { continue }
            if same && f.id == "jpeg-small" && !["jpg", "jpeg", "jpe"].contains(e) { continue }
            out.append(ConvTarget(id: "image.\(f.id)", label: f.label, detail: f.detail, group: "Images", ext: f.ext) { ctx in
                try write(ctx.input, to: ctx.output, format: f)
                return [ctx.output]
            })
        }
        if e == "gif" { out.insert(GifToVideo.target, at: 0) }
        out.append(pdfTarget)
        out.append(ocrTarget)
        return out
    }

    // MARK: Lecture / écriture

    static func load(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ConvError.failed("Unreadable image") }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,      // applique l'orientation EXIF
            kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1),
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) { return cg }
        if let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) { return cg }
        throw ConvError.failed("Unreadable image")
    }

    private static func scaled(_ cg: CGImage, maxSide: Int, square: Bool) -> CGImage {
        let w = cg.width, h = cg.height
        let scale = min(1.0, Double(maxSide) / Double(max(w, h)))
        var nw = max(1, Int(Double(w) * scale)), nh = max(1, Int(Double(h) * scale))
        if square { nw = maxSide; nh = maxSide }
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.interpolationQuality = .high
        let dw = Double(w) * (square ? Double(maxSide) / Double(max(w, h)) : scale)
        let dh = Double(h) * (square ? Double(maxSide) / Double(max(w, h)) : scale)
        ctx.draw(cg, in: CGRect(x: (Double(nw) - dw) / 2, y: (Double(nh) - dh) / 2, width: dw, height: dh))
        return ctx.makeImage() ?? cg
    }

    private static func flattened(_ cg: CGImage) -> CGImage {
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return cg }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage() ?? cg
    }

    static func write(_ input: URL, to output: URL, format f: Format) throws {
        var cg = try load(input)
        if f.flatten { cg = flattened(cg) }
        // Icônes : image carrée (marges transparentes) en plusieurs tailles, comme les vrais fichiers d'icône.
        if let m = f.maxSide {
            let sizes = f.id == "ico" ? [16, 32, 48, 64, 128, 256] : [16, 32, 128, 256, 512]
            guard let dest = CGImageDestinationCreateWithURL(output as CFURL, f.type as CFString, sizes.count, nil) else {
                throw ConvError.failed("This format can't be written")
            }
            let base = scaled(cg, maxSide: m, square: true)
            for size in sizes { CGImageDestinationAddImage(dest, size == m ? base : scaled(base, maxSide: size, square: true), nil) }
            guard CGImageDestinationFinalize(dest) else { throw ConvError.failed("Writing failed") }
            return
        }
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, f.type as CFString, 1, nil) else {
            throw ConvError.failed("This format can't be written")
        }
        var props: [CFString: Any] = [:]
        if let q = f.quality { props[kCGImageDestinationLossyCompressionQuality] = q }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConvError.failed("Writing failed") }
    }

    // MARK: PDF

    static let pdfTarget = ConvTarget(id: "image.pdf", label: "PDF", detail: "one page", group: "Documents", ext: "pdf") { ctx in
        try writePDF(images: [ctx.input], to: ctx.output)
        return [ctx.output]
    }

    static let mergePDF = ConvTarget(id: "image.pdf-merge", label: "One PDF", detail: "all images", group: "Documents",
                                     ext: "pdf", mode: .merge) { ctx in
        try writePDF(images: ctx.inputs, to: ctx.output)
        return [ctx.output]
    }

    static func writePDF(images: [URL], to out: URL) throws {
        let doc = PDFDocument()
        for (i, u) in images.enumerated() {
            let cg = try load(u)
            let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            guard let page = PDFPage(image: ns) else { throw ConvError.failed("Couldn't build a PDF page") }
            doc.insert(page, at: i)
        }
        guard doc.write(to: out) else { throw ConvError.failed("Writing failed") }
    }

    // MARK: OCR

    static let ocrTarget = ConvTarget(id: "image.ocr", label: "Text (OCR)", detail: "reads the text", group: "Text", ext: "txt") { ctx in
        let text = try recognize(try load(ctx.input))
        guard !text.isEmpty else { throw ConvError.failed("No text found") }
        try text.write(to: ctx.output, atomically: true, encoding: .utf8)
        return [ctx.output]
    }

    static func recognize(_ cg: CGImage) throws -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}

// MARK: - PDF

enum PDFConv {
    static func targets(for url: URL) -> [ConvTarget] {
        var t: [ConvTarget] = []
        for (id, label, ext, type, q) in [("png", "PNG", "png", "public.png", 1.0), ("jpeg", "JPEG", "jpg", "public.jpeg", 0.9),
                                          ("tiff", "TIFF", "tiff", "public.tiff", 1.0)] {
            t.append(ConvTarget(id: "pdf.\(id)", label: label, detail: "one image per page", group: "Images", ext: ext) { ctx in
                try renderPages(ctx.input, to: ctx.output, ext: ext, type: type, quality: q, progress: ctx.progress)
            })
        }
        t.append(ConvTarget(id: "pdf.txt", label: "Text", detail: "selectable text", group: "Text", ext: "txt") { ctx in
            guard let doc = PDFDocument(url: ctx.input) else { throw ConvError.failed("Unreadable PDF") }
            let s = doc.string ?? ""
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConvError.failed("This PDF has no selectable text — try Text (OCR)")
            }
            try s.write(to: ctx.output, atomically: true, encoding: .utf8)
            return [ctx.output]
        })
        t.append(ConvTarget(id: "pdf.ocr", label: "Text (OCR)", detail: "scanned PDFs", group: "Text", ext: "txt") { ctx in
            guard let doc = PDFDocument(url: ctx.input) else { throw ConvError.failed("Unreadable PDF") }
            var parts: [String] = []
            for i in 0..<doc.pageCount {
                try Task.checkCancellation()
                guard let page = doc.page(at: i), let cg = render(page, scale: 2.5) else { continue }
                parts.append(try ImageConv.recognize(cg))
                ctx.progress(Double(i + 1) / Double(doc.pageCount))
            }
            let s = parts.joined(separator: "\n\n")
            guard !s.isEmpty else { throw ConvError.failed("No text found") }
            try s.write(to: ctx.output, atomically: true, encoding: .utf8)
            return [ctx.output]
        })
        return t
    }

    static let mergeTarget = ConvTarget(id: "pdf.merge", label: "Merge", detail: "one PDF", group: "Documents", ext: "pdf",
                                        mode: .merge) { ctx in
        let out = PDFDocument()
        for u in ctx.inputs {
            guard let d = PDFDocument(url: u) else { throw ConvError.failed("Unreadable PDF") }
            for i in 0..<d.pageCount { if let p = d.page(at: i) { out.insert(p, at: out.pageCount) } }
        }
        guard out.write(to: ctx.output) else { throw ConvError.failed("Writing failed") }
        return [ctx.output]
    }

    static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let rot = page.rotation % 180 != 0
        let w = Int((rot ? box.height : box.width) * scale), h = Int((rot ? box.width : box.height) * scale)
        guard w > 0, h > 0, w < 20_000, h < 20_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: CGFloat(w) / (rot ? box.height : box.width), y: CGFloat(h) / (rot ? box.width : box.height))
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    static func renderPages(_ input: URL, to output: URL, ext: String, type: String, quality: Double,
                            progress: @Sendable (Double) -> Void) throws -> [URL] {
        guard let doc = PDFDocument(url: input), doc.pageCount > 0 else { throw ConvError.failed("Unreadable PDF") }
        let fm = FileManager.default
        var folder = output
        let single = doc.pageCount == 1
        if !single {
            folder = ConvNaming.freeFolder(named: input.deletingPathExtension().lastPathComponent + " pages",
                                           in: output.deletingLastPathComponent())
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        var made: [URL] = []
        for i in 0..<doc.pageCount {
            try Task.checkCancellation()
            guard let page = doc.page(at: i), let cg = render(page, scale: 2) else { continue }
            let dest = single ? output : folder.appendingPathComponent("page \(String(format: "%03d", i + 1)).\(ext)")
            guard let d = CGImageDestinationCreateWithURL(dest as CFURL, type as CFString, 1, nil) else { throw ConvError.unsupported }
            CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(d) else { throw ConvError.failed("Writing failed") }
            made.append(dest)
            progress(Double(i + 1) / Double(doc.pageCount))
        }
        return single ? made : [folder]
    }
}
