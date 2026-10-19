import Foundation

/// Cola con un máximo de trabajos simultáneos; el resto espera en FIFO (§5.3).
actor ConversionQueue {
    static let shared = ConversionQueue(limit: 4)

    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    private func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
        // El hueco lo ha cedido `release` sin decrementar `running`
    }

    private func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        do {
            let value = try await work()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }
}

struct JobError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Ejecuta un trabajo de Convertir o Herramientas sobre un archivo: valida, procesa en un
/// temporal y mueve el resultado a su nombre final (§4).
enum JobRunner {
    struct Output: Sendable {
        var url: URL
        /// Se guardó en Descargas porque la carpeta original no admite escritura.
        var usedFallback: Bool
    }

    typealias Progress = @Sendable (Double) -> Void

    static func run(_ file: DraggedFile, _ operation: SliceOperation, progress: @escaping Progress) async throws -> Output {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.url.path) else { throw JobError("El archivo ya no existe") }
        let cloud = try? file.url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if cloud?.isUbiquitousItem == true, cloud?.ubiquitousItemDownloadingStatus != .current {
            throw JobError("Descarga el archivo de iCloud primero")
        }

        var plan = OutputWriter.plan(for: file.url)
        let tmpDir = try OutputWriter.makeTemporaryDirectory(near: plan.directory)
        ProcessRegistry.shared.addTemporary(tmpDir)
        defer {
            try? fm.removeItem(at: tmpDir)
            ProcessRegistry.shared.removeTemporary(tmpDir)
        }

        let produced = try await produce(file, operation, in: tmpDir, progress: progress)
        try Task.checkCancellation()

        let final: URL
        do {
            final = try OutputWriter.commit(produced.file, into: plan.directory, base: produced.base, ext: produced.ext)
        } catch where OutputWriter.isPermissionError(error) && !plan.usedFallback {
            // Permiso denegado al escribir junto al original → Descargas
            plan = .init(directory: OutputWriter.downloadsDirectory, usedFallback: true)
            final = try OutputWriter.commit(produced.file, into: plan.directory, base: produced.base, ext: produced.ext)
        }
        progress(1)
        Log.conversion.info("Creado \(final.path, privacy: .public)")
        return Output(url: final, usedFallback: plan.usedFallback)
    }

    private struct Produced {
        var file: URL
        var base: String
        var ext: String
    }

    private static func produce(_ file: DraggedFile, _ operation: SliceOperation, in tmpDir: URL,
                                progress: @escaping Progress) async throws -> Produced {
        let src = file.url
        func tmp(_ ext: String) -> URL { tmpDir.appendingPathComponent("salida.\(ext)") }

        switch operation {
        case .convert(let target) where target.isAudio:
            let info = try await probeAudio(src)
            let out = tmp(target.fileExtension)
            let args = AudioConverter.arguments(input: src, output: out, target: target, info: info,
                                                isVideoSource: file.kind == .video, aacAT: Binaries.hasAACAT)
            try await ffmpeg(args, duration: info.duration, range: 0...1, progress: progress)
            return Produced(file: out, base: OutputNaming.baseName(for: src), ext: target.fileExtension)

        case .convert(let target):
            let out = tmp(target.fileExtension)
            try await ImageConverter.convert(input: src, to: target, output: out)
            return Produced(file: out, base: OutputNaming.baseName(for: src), ext: target.fileExtension)

        case .tool(let tool) where file.kind == .image:
            switch tool {
            case .compress:
                let out = tmp("img")
                let ext = try ImageTools.compress(input: src, output: out)
                return Produced(file: out, base: OutputNaming.baseName(for: src, suffix: "_compressed"), ext: ext)
            case .metadata:
                let ext = src.pathExtension
                let out = tmp(ext)
                try ImageTools.stripMetadata(input: src, output: out)
                return Produced(file: out, base: OutputNaming.baseName(for: src, suffix: "_clean"), ext: ext)
            default:
                throw JobError("Herramienta no válida para imágenes")
            }

        case .tool(let tool):
            let info = try await probeAudio(src)
            switch tool {
            case .normalize:
                let target = AudioConverter.sameFormatTarget(for: src)
                let measure = try await ffmpeg(AudioConverter.loudnormMeasureArguments(input: src),
                                               duration: info.duration, range: 0...0.5, progress: progress)
                guard let m = AudioConverter.parseLoudnorm(measure.stderr) else {
                    throw JobError("No se pudo medir el volumen (¿audio en silencio?)")
                }
                var opts = AudioConverter.Options()
                opts.audioFilter = AudioConverter.loudnormApplyFilter(m)
                opts.forceSampleRate = true
                let out = tmp(target.fileExtension)
                try await ffmpeg(AudioConverter.arguments(input: src, output: out, target: target, info: info,
                                                          isVideoSource: file.kind == .video, aacAT: Binaries.hasAACAT, options: opts),
                                 duration: info.duration, range: 0.5...1, progress: progress)
                return Produced(file: out, base: OutputNaming.baseName(for: src, suffix: "_normalized"), ext: target.fileExtension)

            case .compress:
                var opts = AudioConverter.Options()
                opts.mp3VBR = true
                let out = tmp("mp3")
                try await ffmpeg(AudioConverter.arguments(input: src, output: out, target: .mp3, info: info,
                                                          isVideoSource: file.kind == .video, aacAT: Binaries.hasAACAT, options: opts),
                                 duration: info.duration, range: 0...1, progress: progress)
                return Produced(file: out, base: OutputNaming.baseName(for: src, suffix: "_compressed"), ext: "mp3")

            case .channels:
                let toMono = (info.audio?.channels ?? 1) >= 2
                let target = AudioConverter.sameFormatTarget(for: src)
                var opts = AudioConverter.Options()
                opts.channels = toMono ? 1 : 2
                let out = tmp(target.fileExtension)
                try await ffmpeg(AudioConverter.arguments(input: src, output: out, target: target, info: info,
                                                          isVideoSource: file.kind == .video, aacAT: Binaries.hasAACAT, options: opts),
                                 duration: info.duration, range: 0...1, progress: progress)
                return Produced(file: out, base: OutputNaming.baseName(for: src, suffix: toMono ? "_mono" : "_stereo"),
                                ext: target.fileExtension)

            case .metadata:
                let ext = src.pathExtension
                let out = tmp(ext)
                try await ffmpeg(AudioConverter.stripMetadataArguments(input: src, output: out),
                                 duration: info.duration, range: 0...1, progress: progress)
                return Produced(file: out, base: OutputNaming.baseName(for: src, suffix: "_clean"), ext: ext)
            }

        case .action:
            throw JobError("Las acciones no pasan por la cola")
        }
    }

    private static func probeAudio(_ url: URL) async throws -> MediaInfo {
        let info: MediaInfo
        do {
            info = try await MediaProbe.probe(url)
        } catch {
            throw JobError(error.localizedDescription)
        }
        guard info.audio != nil else { throw JobError("El archivo no tiene audio") }
        return info
    }

    /// Ejecuta ffmpeg y traduce `out_time_us` a progreso dentro de `range`.
    @discardableResult
    private static func ffmpeg(_ args: [String], duration: Double?, range: ClosedRange<Double>,
                               progress: @escaping Progress) async throws -> FFmpegRunner.Result {
        let total = (duration ?? 0) * 1_000_000
        let result = try await FFmpegRunner.run(executable: Binaries.ffmpeg, arguments: args) { us in
            guard total > 0 else { return }
            let fraction = min(max(Double(us) / total, 0), 1)
            progress(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
        }
        try Task.checkCancellation()
        guard result.status == 0 else { throw JobError(FFmpegRunner.summarize(result.stderr)) }
        return result
    }
}
