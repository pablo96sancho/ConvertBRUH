import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ConvertBRUH

/// Pipeline completo con el ffmpeg real de Resources/bin. Se salta si no está descargado.
@Suite(.enabled(if: FileManager.default.isExecutableFile(atPath: Binaries.ffmpeg.path)), .serialized)
struct IntegracionTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: Utilidades

    private func ffmpeg(_ args: [String]) async throws {
        let r = try await FFmpegRunner.run(executable: Binaries.ffmpeg, arguments: ["-hide_banner", "-loglevel", "error", "-y"] + args)
        #expect(r.status == 0, "\(r.stderr)")
    }

    private func dragged(_ url: URL) -> DraggedFile {
        var f = DraggedFile(url: url, kind: FileKind.classify(url))
        if f.kind == .video { f.videoHasAudio = MediaProbe.hasAudioStreamSync(url) }
        return f
    }

    private func run(_ url: URL, _ op: SliceOperation) async throws -> URL {
        try await JobRunner.run(dragged(url), op) { _ in }.url
    }

    // MARK: Audio

    @Test func flac24_96() async throws {
        let src = dir.appendingPathComponent("@Hi: Res 🔥.flac")
        try await ffmpeg(["-f", "lavfi", "-i", "sine=f=440:d=2:sample_rate=96000", "-ac", "2",
                          "-c:a", "flac", "-sample_fmt", "s32", "-bits_per_raw_sample", "24", "file:" + src.path])

        let wav = try await MediaProbe.probe(run(src, .convert(.wav)))
        #expect(wav.audio?.sampleRate == 96000)
        #expect(wav.audio?.codec == "pcm_s24le")

        let mp3URL = try await run(src, .convert(.mp3))
        #expect(mp3URL.lastPathComponent == "@Hi: Res 🔥.mp3")
        #expect(try await MediaProbe.probe(mp3URL).audio?.sampleRate == 48000)
        #expect(try await MediaProbe.probe(run(src, .convert(.m4a))).audio?.sampleRate == 48000)

        // Repetir → (1)
        #expect(try await run(src, .convert(.mp3)).lastPathComponent == "@Hi: Res 🔥 (1).mp3")
    }

    @Test func caratulaYTags() async throws {
        let cover = dir.appendingPathComponent("cover.jpg")
        let src = dir.appendingPathComponent("tema.mp3")
        try await ffmpeg(["-f", "lavfi", "-i", "color=c=red:s=300x300", "-frames:v", "1", "file:" + cover.path])
        try await ffmpeg(["-f", "lavfi", "-i", "sine=f=440:d=2", "-i", "file:" + cover.path, "-map", "0:a", "-map", "1:v",
                          "-c:a", "libmp3lame", "-c:v", "copy", "-disposition:v:0", "attached_pic", "-id3v2_version", "3",
                          "-metadata", "title=Prueba", "file:" + src.path])
        for target in [TargetFormat.m4a, .flac] {
            let out = try await run(src, .convert(target))
            let info = try await MediaProbe.probe(out)
            #expect(info.attachedPicVideoIndex != nil, "\(target) sin carátula")
            let tags = try await FFmpegRunner.run(executable: Binaries.ffprobe, arguments: [
                "-v", "error", "-show_entries", "format_tags=title", "-of", "csv=p=0", "file:" + out.path])
            #expect(tags.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "Prueba", "\(target) sin tags")
        }
        // METADATA: sin tags ni carátula, sin recodificar
        let clean = try await run(src, .tool(.metadata))
        #expect(clean.lastPathComponent == "tema_clean.mp3")
        #expect(try await MediaProbe.probe(clean).attachedPicVideoIndex == nil)
    }

    @Test func videoSoloAudio() async throws {
        let src = dir.appendingPathComponent("clip.mov")
        try await ffmpeg(["-f", "lavfi", "-i", "testsrc=s=160x120:d=2", "-f", "lavfi", "-i", "sine=d=2",
                          "-c:v", "libx264", "-c:a", "aac", "-shortest", "file:" + src.path])
        let f = dragged(src)
        #expect(f.kind == .video && f.videoHasAudio == true)
        let out = try await run(src, .convert(.mp3))
        let info = try await MediaProbe.probe(out)
        #expect(info.audio != nil && info.attachedPicVideoIndex == nil)

        let mudo = dir.appendingPathComponent("mudo.mov")
        try await ffmpeg(["-f", "lavfi", "-i", "testsrc=s=160x120:d=1", "-c:v", "libx264", "file:" + mudo.path])
        #expect(TargetFormat.available(for: [dragged(mudo)]).isEmpty)
    }

    @Test func normalizeYChannels() async throws {
        let src = dir.appendingPathComponent("bajo.wav")
        try await ffmpeg(["-f", "lavfi", "-i", "sine=f=440:d=6,volume=0.1", "-ac", "2", "-c:a", "pcm_s24le", "file:" + src.path])

        let norm = try await run(src, .tool(.normalize))
        #expect(norm.lastPathComponent == "bajo_normalized.wav")
        let ninfo = try await MediaProbe.probe(norm)
        #expect(ninfo.audio?.sampleRate == 44100)
        #expect(ninfo.audio?.codec == "pcm_s24le")
        let r = try await FFmpegRunner.run(executable: Binaries.ffmpeg, arguments: [
            "-hide_banner", "-nostdin", "-i", "file:" + norm.path, "-af", "ebur128", "-f", "null", "-"])
        let line = r.stderr.split(separator: "\n").last { $0.contains("I:") && $0.contains("LUFS") }
        let lufs = line.flatMap { Double($0.split(separator: " ").dropFirst().first ?? "") }
        #expect(lufs.map { abs($0 + 14) <= 0.5 } == true, "LUFS: \(String(describing: line))")

        let mono = try await run(src, .tool(.channels))
        #expect(mono.lastPathComponent == "bajo_mono.wav")
        #expect(try await MediaProbe.probe(mono).audio?.channels == 1)

        let comp = try await run(src, .tool(.compress))
        #expect(comp.lastPathComponent == "bajo_compressed.mp3")
    }

    @Test func errores() async throws {
        let borrado = dir.appendingPathComponent("no-existe.wav")
        await #expect(throws: JobError.self) { try await run(borrado, .convert(.mp3)) }
        let corrupto = dir.appendingPathComponent("roto.wav")
        try Data("esto no es audio".utf8).write(to: corrupto)
        await #expect(throws: (any Error).self) { try await run(corrupto, .convert(.mp3)) }
        // No quedan archivos a medias
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("roto.mp3").path))
    }

    // MARK: Imagen

    private func makeImage(_ name: String, type: String, alpha: Bool, orientation: Int = 1, gps: Bool = false) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let ctx = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200)) // mitad derecha transparente si alpha
        let d = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
        var props: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if gps { props[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 40.4, kCGImagePropertyGPSLatitudeRef: "N"] }
        CGImageDestinationAddImage(d, ctx.makeImage()!, props as CFDictionary)
        #expect(CGImageDestinationFinalize(d))
        return url
    }

    private func pixel(_ url: URL, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, w: Int, h: Int) {
        let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        var data = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
        return (data[0], data[1], data[2], img.width, img.height)
    }

    @Test func pngTransparenteAJPGBlanco() async throws {
        let src = try makeImage("logo.png", type: "public.png", alpha: true)
        let jpg = try await run(src, .convert(.jpg))
        let p = pixel(jpg, x: 350, y: 100) // zona transparente
        #expect(p.r > 245 && p.g > 245 && p.b > 245)
    }

    @Test func heicOrientadoAJPGyWebPyPDF() async throws {
        let src = try makeImage("foto.heic", type: "public.heic", alpha: false, orientation: 6)
        let files = [dragged(src)]
        #expect(TargetFormat.available(for: files) == [.jpg, .png, .webp, .pdf])

        let jpg = try await run(src, .convert(.jpg))
        let p = pixel(jpg, x: 0, y: 0)
        #expect(p.w == 200 && p.h == 400) // orientación aplicada
        let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(jpg as CFURL, nil)!, 0, nil) as! [CFString: Any]
        #expect((props[kCGImagePropertyOrientation] as? Int ?? 1) == 1)

        let webp = try await run(src, .convert(.webp))
        #expect(webp.pathExtension == "webp")
        #expect(CGImageSourceGetType(CGImageSourceCreateWithURL(webp as CFURL, nil)!) as String? == "org.webmproject.webp")

        let pdf = try await run(src, .convert(.pdf))
        #expect(try Data(contentsOf: pdf).prefix(5) == Data("%PDF-".utf8))
    }

    @Test func herramientasImagen() async throws {
        let src = try makeImage("gps.jpg", type: "public.jpeg", alpha: false, gps: true)
        let clean = try await run(src, .tool(.metadata))
        #expect(clean.lastPathComponent == "gps_clean.jpg")
        let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(clean as CFURL, nil)!, 0, nil) as! [CFString: Any]
        #expect(props[kCGImagePropertyGPSDictionary] == nil)

        let comp = try await run(src, .tool(.compress))
        #expect(comp.lastPathComponent == "gps_compressed.jpg")
        let alpha = try makeImage("alfa.png", type: "public.png", alpha: true)
        #expect(try await run(alpha, .tool(.compress)).lastPathComponent == "alfa_compressed.png")
    }

    @Test func moveConColision() throws {
        let a = dir.appendingPathComponent("origen", isDirectory: true)
        let b = dir.appendingPathComponent("destino", isDirectory: true)
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try "1".write(to: a.appendingPathComponent("beat.wav"), atomically: true, encoding: .utf8)
        try "2".write(to: b.appendingPathComponent("beat.wav"), atomically: true, encoding: .utf8)
        let final = try FileActions.move(a.appendingPathComponent("beat.wav"), into: b)
        #expect(final?.lastPathComponent == "beat (1).wav")
        #expect(!FileManager.default.fileExists(atPath: a.appendingPathComponent("beat.wav").path))
    }
}
