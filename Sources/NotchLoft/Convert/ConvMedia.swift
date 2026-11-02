import AVFoundation
import AppKit
import CoreGraphics
import CoreVideo
import ImageIO

// MARK: - Audio (afconvert, fourni avec macOS)

enum AudioConv {
    struct Fmt { let id, label, detail, ext, file, data: String; var extra: [String] = [] }

    static let formats: [Fmt] = [
        .init(id: "m4a", label: "M4A · AAC", detail: "256 kbps", ext: "m4a", file: "m4af", data: "aac", extra: ["-b", "256000"]),
        .init(id: "m4a-small", label: "M4A · small", detail: "96 kbps", ext: "m4a", file: "m4af", data: "aac", extra: ["-b", "96000"]),
        .init(id: "alac", label: "M4A · lossless", detail: "Apple Lossless", ext: "m4a", file: "m4af", data: "alac"),
        .init(id: "wav", label: "WAV", detail: "16-bit", ext: "wav", file: "WAVE", data: "LEI16"),
        .init(id: "aiff", label: "AIFF", detail: "16-bit", ext: "aiff", file: "AIFF", data: "BEI16"),
        .init(id: "caf", label: "CAF", detail: "Core Audio", ext: "caf", file: "caff", data: "LEI16"),
        .init(id: "flac", label: "FLAC", detail: "lossless", ext: "flac", file: "flac", data: "flac"),
        .init(id: "aac", label: "AAC", detail: "raw .aac", ext: "aac", file: "adts", data: "aac", extra: ["-b", "192000"]),
    ]

    static func targets(for url: URL) -> [ConvTarget] {
        guard ConvDetect.avAudioExts.contains(ConvDetect.ext(url)) else { return [] }   // ogg/opus/wma : ffmpeg seulement
        let e = ConvDetect.ext(url)
        return formats.compactMap { f in
            if f.ext == e && f.id != "m4a-small" && f.id != "alac" && f.id != "m4a" { return nil }
            return ConvTarget(id: "audio.\(f.id)", label: f.label, detail: f.detail, group: "Audio", ext: f.ext) { ctx in
                try await convert(ctx.input, to: ctx.output, fmt: f)
                return [ctx.output]
            }
        }
    }

    static func convert(_ input: URL, to out: URL, fmt f: Fmt) async throws {
        guard let afconvert = Shell.tool("afconvert") else { throw ConvError.toolMissing("afconvert") }
        try await Shell.check(afconvert, ["-f", f.file, "-d", f.data] + f.extra + [input.path, out.path])
    }
}

// MARK: - Vidéo (AVFoundation)

enum VideoConv {
    static let exportTargets: [(id: String, label: String, detail: String, ext: String, preset: String, type: AVFileType)] = [
        ("mp4-1080", "MP4 · 1080p", "H.264", "mp4", AVAssetExportPreset1920x1080, .mp4),
        ("mp4-720", "MP4 · 720p", "H.264, smaller", "mp4", AVAssetExportPreset1280x720, .mp4),
        ("mp4-480", "MP4 · 480p", "H.264, small", "mp4", AVAssetExportPreset640x480, .mp4),
        ("mp4-hevc", "MP4 · HEVC", "H.265, compact", "mp4", AVAssetExportPresetHEVCHighestQuality, .mp4),
        ("mov", "MOV", "best quality", "mov", AVAssetExportPresetHighestQuality, .mov),
        ("m4v", "M4V", "H.264", "m4v", AVAssetExportPreset1920x1080, .m4v),
    ]

    static func targets(for url: URL) -> [ConvTarget] {
        let e = ConvDetect.ext(url)
        guard ConvDetect.avVideoExts.contains(e) else { return [] }     // mkv/avi/webm… : ffmpeg seulement
        var t: [ConvTarget] = []
        for x in exportTargets where x.ext != e || x.id.hasPrefix("mp4-") {
            t.append(ConvTarget(id: "video.\(x.id)", label: x.label, detail: x.detail, group: "Video", ext: x.ext) { ctx in
                try await export(ctx.input, to: ctx.output, preset: x.preset, type: x.type, progress: ctx.progress)
                return [ctx.output]
            })
        }
        t.append(ConvTarget(id: "video.gif", label: "GIF", detail: "animated, 15 s max", group: "Images", ext: "gif") { ctx in
            try await toGIF(ctx.input, to: ctx.output, progress: ctx.progress)
            return [ctx.output]
        })
        for (id, label, ext, type, q) in [("frame-png", "PNG", "png", "public.png", 1.0), ("frame-jpg", "JPEG", "jpg", "public.jpeg", 0.92)] {
            t.append(ConvTarget(id: "video.\(id)", label: label, detail: "a frame", group: "Images", ext: ext) { ctx in
                try await frame(ctx.input, to: ctx.output, type: type, quality: q)
                return [ctx.output]
            })
        }
        for f in AudioConv.formats where ["m4a", "wav", "aiff", "flac"].contains(f.id) {
            t.append(ConvTarget(id: "video.audio-\(f.id)", label: f.label, detail: "audio only", group: "Audio", ext: f.ext) { ctx in
                try await extractAudio(ctx.input, to: ctx.output, fmt: f)
                return [ctx.output]
            })
        }
        return t
    }

    static func export(_ input: URL, to out: URL, preset: String, type: AVFileType,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: input)
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
        guard compatible.contains(preset) else { throw ConvError.failed("This video can't be exported in that format") }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ConvError.unsupported }
        session.outputURL = out
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        let watcher = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { watcher.cancel() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { c.resume() }
            }
        } onCancel: { session.cancelExport() }
        if Task.isCancelled { try? FileManager.default.removeItem(at: out); throw ConvError.cancelled }
        if session.status != .completed {
            throw ConvError.failed(session.error?.localizedDescription ?? "Export failed")
        }
    }

    static func extractAudio(_ input: URL, to out: URL, fmt: AudioConv.Fmt) async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("notchloft-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await export(input, to: tmp, preset: AVAssetExportPresetAppleM4A, type: .m4a, progress: { _ in })
        if fmt.id == "m4a" { try FileManager.default.moveItem(at: tmp, to: out) } else { try await AudioConv.convert(tmp, to: out, fmt: fmt) }
    }

    static func frame(_ input: URL, to out: URL, type: String, quality: Double) async throws {
        let asset = AVURLAsset(url: input)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .positiveInfinity
        gen.requestedTimeToleranceAfter = .positiveInfinity
        let dur = (try? await asset.load(.duration).seconds) ?? 0
        let t = CMTime(seconds: min(1, max(0, dur / 2)), preferredTimescale: 600)
        let cg = try await gen.image(at: t).image
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, type as CFString, 1, nil) else { throw ConvError.unsupported }
        CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(d) else { throw ConvError.failed("Writing failed") }
    }

    /// GIF animé : 10 images par seconde, 480 px de large au plus, 15 secondes au plus.
    static func toGIF(_ input: URL, to out: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: input)
        let duration = min(15, (try? await asset.load(.duration).seconds) ?? 0)
        guard duration > 0 else { throw ConvError.failed("Unreadable video") }
        let fps = 10.0
        let count = max(1, Int(duration * fps))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)
        gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 20)
        gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "com.compuserve.gif" as CFString, count, nil) else {
            throw ConvError.unsupported
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary
        for i in 0..<count {
            try Task.checkCancellation()
            let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            if let cg = try? await gen.image(at: t).image { CGImageDestinationAddImage(dest, cg, frameProps) }
            progress(Double(i + 1) / Double(count))
        }
        guard CGImageDestinationFinalize(dest) else { throw ConvError.failed("Writing failed") }
    }
}

// MARK: - GIF → MP4 (AVAssetWriter)

enum GifToVideo {
    static let target = ConvTarget(id: "image.gif-mp4", label: "MP4", detail: "from the GIF", group: "Video", ext: "mp4") { ctx in
        try await convert(ctx.input, to: ctx.output, progress: ctx.progress)
        return [ctx.output]
    }

    static func convert(_ input: URL, to out: URL, progress: @Sendable (Double) -> Void) async throws {
        guard let src = CGImageSourceCreateWithURL(input as CFURL, nil) else { throw ConvError.failed("Unreadable GIF") }
        let n = CGImageSourceGetCount(src)
        guard n > 0, let first = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw ConvError.failed("Unreadable GIF") }
        // Dimensions paires, exigées par H.264.
        let w = (first.width / 2) * 2, h = (first.height / 2) * 2
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw ConvError.failed(writer.error?.localizedDescription ?? "Writer failed") }
        writer.startSession(atSourceTime: .zero)
        var time = 0.0
        for i in 0..<n {
            try Task.checkCancellation()
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            var delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            if delay < 0.02 { delay = 0.1 }
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32ARGB, nil, &pb)
            guard let buf = pb else { throw ConvError.failed("Out of memory") }
            CVPixelBufferLockBaseAddress(buf, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            CVPixelBufferUnlockBaseAddress(buf, [])
            adaptor.append(buf, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
            time += delay
            progress(Double(i + 1) / Double(n))
        }
        input.markAsFinished()
        // Dernière image maintenue pendant sa durée.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.endSession(atSourceTime: CMTime(seconds: time, preferredTimescale: 600))
            writer.finishWriting { c.resume() }
        }
        if writer.status != .completed { throw ConvError.failed(writer.error?.localizedDescription ?? "Export failed") }
    }
}

// MARK: - ffmpeg (optionnel : plus de formats si l'outil est installé)

enum FFmpegConv {
    static let path: String? = Shell.tool("ffmpeg")

    /// Encodeurs réellement disponibles dans le ffmpeg installé.
    static let encoders: Set<String> = {
        guard let p = path else { return [] }
        let pr = Process()
        pr.executableURL = URL(fileURLWithPath: p)
        pr.arguments = ["-hide_banner", "-encoders"]
        let pipe = Pipe()
        pr.standardOutput = pipe
        pr.standardError = FileHandle.nullDevice
        guard (try? pr.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        pr.waitUntilExit()
        var set = Set<String>()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts[0].count == 6 { set.insert(String(parts[1])) }
        }
        return set
    }()

    static var available: Bool { path != nil }
    static func has(_ e: String...) -> Bool { e.allSatisfy { encoders.contains($0) } }

    struct Spec {
        let id, label, detail, group, ext: String
        let args: [String]
        let needs: [String]            // encodeurs requis
        let categories: Set<FileCategory>
    }

    static var specs: [Spec] {
        let aac = has("aac") ? "aac" : "libfdk_aac"
        return [
            Spec(id: "mp3", label: "MP3", detail: "audio", group: "Audio", ext: "mp3",
                 args: ["-vn", "-c:a", "libmp3lame", "-q:a", "2"], needs: ["libmp3lame"], categories: [.audio, .video]),
            Spec(id: "ogg", label: "OGG · Vorbis", detail: "audio", group: "Audio", ext: "ogg",
                 args: ["-vn", "-c:a", "libvorbis", "-q:a", "5"], needs: ["libvorbis"], categories: [.audio, .video]),
            Spec(id: "opus", label: "OPUS", detail: "audio", group: "Audio", ext: "opus",
                 args: ["-vn", "-c:a", "libopus", "-b:a", "128k"], needs: ["libopus"], categories: [.audio, .video]),
            Spec(id: "wma", label: "WMA", detail: "audio", group: "Audio", ext: "wma",
                 args: ["-vn", "-c:a", "wmav2", "-b:a", "192k"], needs: ["wmav2"], categories: [.audio, .video]),
            Spec(id: "ac3", label: "AC3", detail: "audio", group: "Audio", ext: "ac3",
                 args: ["-vn", "-c:a", "ac3", "-b:a", "192k"], needs: ["ac3"], categories: [.audio, .video]),
            Spec(id: "m4a", label: "M4A", detail: "audio", group: "Audio", ext: "m4a",
                 args: ["-vn", "-c:a", aac, "-b:a", "192k"], needs: [aac], categories: [.audio]),
            Spec(id: "mp4", label: "MP4 · H.264", detail: "video", group: "Video", ext: "mp4",
                 args: ["-c:v", "libx264", "-crf", "23", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", aac, "-movflags", "+faststart"],
                 needs: ["libx264", aac], categories: [.video]),
            Spec(id: "mp4-hevc", label: "MP4 · H.265", detail: "video, compact", group: "Video", ext: "mp4",
                 args: ["-c:v", "libx265", "-crf", "28", "-tag:v", "hvc1", "-pix_fmt", "yuv420p", "-c:a", aac, "-movflags", "+faststart"],
                 needs: ["libx265", aac], categories: [.video]),
            Spec(id: "mkv", label: "MKV", detail: "video", group: "Video", ext: "mkv",
                 args: has("libx264") ? ["-c:v", "libx264", "-crf", "23", "-pix_fmt", "yuv420p", "-c:a", aac] : ["-c:v", "mpeg4", "-q:v", "4", "-c:a", aac],
                 needs: [aac], categories: [.video]),
            Spec(id: "avi", label: "AVI", detail: "video", group: "Video", ext: "avi",
                 args: ["-c:v", "mpeg4", "-q:v", "4", "-c:a", has("libmp3lame") ? "libmp3lame" : "ac3"], needs: ["mpeg4"], categories: [.video]),
            Spec(id: "webm", label: "WebM", detail: "video", group: "Video", ext: "webm",
                 args: ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-c:a", "libopus"], needs: ["libvpx-vp9", "libopus"], categories: [.video]),
            Spec(id: "wmv", label: "WMV", detail: "video", group: "Video", ext: "wmv",
                 args: ["-c:v", "wmv2", "-q:v", "4", "-c:a", "wmav2"], needs: ["wmv2", "wmav2"], categories: [.video]),
            Spec(id: "flv", label: "FLV", detail: "video", group: "Video", ext: "flv",
                 args: ["-c:v", "flv", "-q:v", "4", "-c:a", has("libmp3lame") ? "libmp3lame" : aac], needs: ["flv"], categories: [.video]),
            Spec(id: "mpg", label: "MPEG-2", detail: "video", group: "Video", ext: "mpg",
                 args: ["-c:v", "mpeg2video", "-q:v", "4", "-c:a", "mp2"], needs: ["mpeg2video", "mp2"], categories: [.video]),
            Spec(id: "gif", label: "GIF", detail: "animated", group: "Images", ext: "gif",
                 args: ["-an", "-t", "15", "-vf", "fps=12,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse"],
                 needs: [], categories: [.video]),
            Spec(id: "webp", label: "WebP", detail: "web", group: "Images", ext: "webp",
                 args: ["-c:v", "libwebp", "-quality", "85", "-frames:v", "1"], needs: ["libwebp"], categories: [.image]),
            Spec(id: "avif", label: "AVIF", detail: "web", group: "Images", ext: "avif",
                 args: ["-c:v", has("libsvtav1") ? "libsvtav1" : (has("libaom-av1") ? "libaom-av1" : "librav1e"), "-frames:v", "1", "-pix_fmt", "yuv420p"],
                 needs: [], categories: [.image]),
            Spec(id: "jxl", label: "JPEG XL", detail: "", group: "Images", ext: "jxl",
                 args: ["-c:v", "libjxl", "-frames:v", "1"], needs: ["libjxl"], categories: [.image]),
            Spec(id: "tga", label: "TGA", detail: "", group: "Images", ext: "tga", args: ["-frames:v", "1"], needs: ["targa"], categories: [.image]),
            Spec(id: "ppm", label: "PPM", detail: "", group: "Images", ext: "ppm", args: ["-frames:v", "1"], needs: ["ppm"], categories: [.image]),
        ]
    }

    static func targets(for url: URL, category: FileCategory) -> [ConvTarget] {
        guard let ff = path else { return [] }
        let e = ConvDetect.ext(url)
        var out: [ConvTarget] = []
        for s in specs where s.categories.contains(category) {
            if s.ext == e { continue }
            if !s.needs.allSatisfy({ encoders.contains($0) }) { continue }
            // Les formats déjà gérés par macOS ne sont pas doublés.
            if category == .image, ImageConv.writable.contains(ImageConv.formats.first { $0.ext == s.ext }?.type ?? "") { continue }
            if category == .audio, ConvDetect.avAudioExts.contains(e), AudioConv.formats.contains(where: { $0.ext == s.ext }) { continue }
            if category == .video, ConvDetect.avVideoExts.contains(e), ["mp4", "gif", "m4a"].contains(s.ext) { continue }
            out.append(ConvTarget(id: "ff.\(category.rawValue).\(s.id)", label: s.label, detail: s.detail, group: s.group, ext: s.ext) { ctx in
                try await run(ff, ctx.input, ctx.output, args: s.args)
                return [ctx.output]
            })
        }
        return out
    }

    static func run(_ ff: String, _ input: URL, _ out: URL, args: [String]) async throws {
        try await Shell.check(ff, ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", input.path] + args + [out.path])
    }
}
