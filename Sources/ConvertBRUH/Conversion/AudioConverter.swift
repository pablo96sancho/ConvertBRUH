import Foundation

/// Resolución de las salidas sin pérdida (§5.1).
enum BitDepth: Equatable {
    case s16, s24, f32
}

/// Construcción de argumentos de ffmpeg para audio. Todo puro: no ejecuta nada.
enum AudioConverter {
    /// Ajustes extra que usan las herramientas sobre la conversión normal.
    struct Options: Equatable {
        /// MP3 en VBR `-q:a 5` en vez de 320 kbps (herramienta COMPRESS).
        var mp3VBR = false
        /// Filtro de audio (`-af`), p. ej. loudnorm.
        var audioFilter: String?
        /// Forzar número de canales (herramienta CHANNELS).
        var channels: Int?
        /// Forzar `-ar` aunque no cambie (loudnorm remuestrea internamente a 192 kHz).
        var forceSampleRate = false
    }

    static func isLossless(codec: String) -> Bool {
        codec.hasPrefix("pcm_") || ["flac", "alac", "wavpack", "tta", "ape", "mlp", "truehd"].contains(codec)
    }

    /// Bit depth de salida para WAV/AIFF/FLAC.
    static func bitDepth(for audio: MediaInfo.Audio?, target: TargetFormat) -> BitDepth {
        guard let audio, isLossless(codec: audio.codec) else { return .s16 }
        let depth: BitDepth
        if audio.sampleFormat.hasPrefix("flt") || audio.sampleFormat.hasPrefix("dbl")
            || audio.codec.hasPrefix("pcm_f") {
            depth = .f32
        } else {
            let bits = audio.bitsPerRawSample > 0 ? audio.bitsPerRawSample : audio.bitsPerSample
            if bits > 16 {
                depth = .s24
            } else if bits > 0 {
                depth = .s16
            } else {
                // Sin dato de bits: se deduce del formato de muestra
                depth = audio.sampleFormat.hasPrefix("s16") || audio.sampleFormat.hasPrefix("u8") ? .s16 : .s24
            }
        }
        // FLAC no admite float
        if target == .flac && depth == .f32 { return .s24 }
        return depth
    }

    /// Sample rate de salida: se mantiene salvo MP3/M4A por encima de 48 kHz.
    static func outputSampleRate(source: Int, target: TargetFormat) -> Int {
        guard target == .mp3 || target == .m4a, source > 48000 else { return source }
        return source % 44100 == 0 ? 44100 : 48000
    }

    /// Formato de salida de las herramientas que mantienen el formato: el del original,
    /// o WAV si el original no es uno de nuestros formatos (vídeo, OGG, OPUS…).
    static func sameFormatTarget(for source: URL) -> TargetFormat {
        if let f = TargetFormat(fileExtension: source.pathExtension), f.isAudio { return f }
        return .wav
    }

    static func baseArguments(input: URL) -> [String] {
        ["-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1", "-nostats", "-i", "file:" + input.path]
    }

    /// Conversión completa a `target`.
    static func arguments(input: URL, output: URL, target: TargetFormat, info: MediaInfo,
                          isVideoSource: Bool, aacAT: Bool, options: Options = Options()) -> [String] {
        precondition(target.isAudio)
        var args = baseArguments(input: input)
        args += ["-map", "0:a:0"]

        // Carátula: solo de audio con attached_pic hacia MP3/M4A/FLAC
        if !isVideoSource, let pic = info.attachedPicVideoIndex, [.mp3, .m4a, .flac].contains(target) {
            args += ["-map", "0:v:\(pic)", "-c:v", "copy", "-disposition:v:0", "attached_pic"]
        } else {
            args += ["-vn"]
        }
        args += ["-map_metadata", "0"]

        // Sample rate
        let sourceRate = info.audio?.sampleRate ?? 0
        var resampleRate: Int?
        if sourceRate > 0 {
            let rate = outputSampleRate(source: sourceRate, target: target)
            if rate != sourceRate || options.forceSampleRate { resampleRate = rate }
        }
        let depth = bitDepth(for: info.audio, target: target)

        var filters = [options.audioFilter, resampleFilter(rate: resampleRate, ditherTo16: [.wav, .aiff, .flac].contains(target) && depth == .s16)]
            .compactMap { $0 }
        // loudnorm entrega de golpe todo lo que tiene en búfer (~3 s); en audios cortos ese bloque
        // supera el máximo de FLAC y el codificador no arranca
        if target == .flac && options.audioFilter != nil { filters.append("asetnsamples=n=4096") }
        if !filters.isEmpty { args += ["-af", filters.joined(separator: ",")] }

        // Canales
        let sourceChannels = info.audio?.channels ?? 0
        if let ch = options.channels {
            args += ["-ac", String(ch)]
        } else if target == .mp3 && sourceChannels > 2 {
            args += ["-ac", "2"]
        }

        if let resampleRate { args += ["-ar", String(resampleRate)] }

        // Códec
        switch target {
        case .mp3:
            args += ["-c:a", "libmp3lame"]
            args += options.mp3VBR ? ["-q:a", "5"] : ["-b:a", "320k"]
            args += ["-id3v2_version", "3"]
        case .m4a:
            args += ["-c:a", aacAT ? "aac_at" : "aac", "-b:a", "256k", "-movflags", "+faststart"]
        case .wav:
            args += ["-c:a", ["s16": "pcm_s16le", "s24": "pcm_s24le", "f32": "pcm_f32le"][key(depth)]!]
        case .aiff:
            args += ["-c:a", ["s16": "pcm_s16be", "s24": "pcm_s24be", "f32": "pcm_f32be"][key(depth)]!]
        case .flac:
            args += ["-c:a", "flac", "-compression_level", "8"]
            args += depth == .s16 ? ["-sample_fmt", "s16"] : ["-sample_fmt", "s32", "-bits_per_raw_sample", "24"]
        default:
            break
        }

        args += ["-y", "file:" + output.path]
        return args
    }

    /// `aresample` explícito: filtro más largo al cambiar de sample rate (el ffmpeg incluido no trae soxr)
    /// y dither TPDF al bajar a 16 bits. Si ya es s16, swresample no convierte y el dither no se aplica.
    static func resampleFilter(rate: Int?, ditherTo16: Bool) -> String? {
        var params: [String] = []
        if let rate { params += [String(rate), "filter_size=64", "phase_shift=14", "linear_interp=1"] }
        if ditherTo16 { params += ["osf=s16", "dither_method=triangular_hp"] }
        return params.isEmpty ? nil : "aresample=" + params.joined(separator: ":")
    }

    private static func key(_ d: BitDepth) -> String {
        switch d { case .s16: "s16"; case .s24: "s24"; case .f32: "f32" }
    }

    // MARK: - Herramientas

    static let loudnormTarget = "I=-14:TP=-1:LRA=11"

    /// Primera pasada de NORMALIZE: solo mide.
    static func loudnormMeasureArguments(input: URL) -> [String] {
        ["-hide_banner", "-nostdin", "-loglevel", "info", "-progress", "pipe:1", "-nostats",
         "-i", "file:" + input.path, "-map", "0:a:0", "-af", "loudnorm=\(loudnormTarget):print_format=json", "-f", "null", "-"]
    }

    struct LoudnormMeasurement: Equatable {
        var inputI, inputTP, inputLRA, inputThresh, targetOffset: String
    }

    /// Extrae el JSON que imprime loudnorm al final del stderr.
    static func parseLoudnorm(_ stderr: String) -> LoudnormMeasurement? {
        guard let open = stderr.range(of: "{", options: .backwards),
              let close = stderr.range(of: "}", options: .backwards), open.lowerBound < close.lowerBound else { return nil }
        let json = String(stderr[open.lowerBound...close.lowerBound])
        guard let dict = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String],
              let i = dict["input_i"], let tp = dict["input_tp"], let lra = dict["input_lra"],
              let th = dict["input_thresh"], let off = dict["target_offset"] else { return nil }
        // Silencio absoluto: loudnorm devuelve -inf y no se puede normalizar
        guard Double(i)?.isFinite == true else { return nil }
        return .init(inputI: i, inputTP: tp, inputLRA: lra, inputThresh: th, targetOffset: off)
    }

    static func loudnormApplyFilter(_ m: LoudnormMeasurement) -> String {
        "loudnorm=\(loudnormTarget):measured_I=\(m.inputI):measured_TP=\(m.inputTP):measured_LRA=\(m.inputLRA)"
            + ":measured_thresh=\(m.inputThresh):offset=\(m.targetOffset):linear=true"
    }

    /// METADATA: copia el audio sin recodificar y sin tags ni carátula.
    static func stripMetadataArguments(input: URL, output: URL) -> [String] {
        baseArguments(input: input) + ["-map", "0:a:0", "-c", "copy", "-map_metadata", "-1", "-map_chapters", "-1",
                                       "-y", "file:" + output.path]
    }
}
