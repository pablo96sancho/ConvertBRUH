import Foundation

/// Argumentos de ffmpeg para vídeo. Todo puro: no ejecuta nada.
/// Regla general: si el códec ya vale para el contenedor de destino se copia sin recodificar
/// (instantáneo y sin pérdida); si no, H.264 + AAC.
enum VideoConverter {
    /// Códecs de vídeo que caben tal cual en cada contenedor.
    static func canCopyVideo(_ codec: String, to target: TargetFormat) -> Bool {
        switch target {
        case .mp4: return ["h264", "hevc"].contains(codec)
        case .mov: return ["h264", "hevc", "prores"].contains(codec)
        default: return false
        }
    }

    /// Códecs de audio que caben tal cual en cada contenedor.
    static func canCopyAudio(_ codec: String, to target: TargetFormat) -> Bool {
        switch target {
        case .mp4: return ["aac", "mp3", "alac"].contains(codec)
        case .mov: return ["aac", "mp3", "alac"].contains(codec) || codec.hasPrefix("pcm_")
        default: return false
        }
    }

    /// Recodificación a H.264 apta para todo (dimensiones pares, yuv420p).
    static let h264Encode = ["-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
                             "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]

    /// MP4 / MOV.
    static func arguments(input: URL, output: URL, target: TargetFormat, info: MediaInfo, aacAT: Bool) -> [String] {
        precondition(target == .mp4 || target == .mov)
        var args = AudioConverter.baseArguments(input: input)
        args += ["-map", "0:v:0", "-map", "0:a:0?"]

        let videoCodec = info.videoCodec ?? ""
        if canCopyVideo(videoCodec, to: target) {
            args += ["-c:v", "copy"]
            // QuickTime e iOS solo reconocen HEVC con la etiqueta hvc1
            if videoCodec == "hevc" { args += ["-tag:v", "hvc1"] }
        } else {
            args += h264Encode
        }

        if let audio = info.audio {
            if canCopyAudio(audio.codec, to: target) {
                args += ["-c:a", "copy"]
            } else {
                args += ["-c:a", aacAT ? "aac_at" : "aac", "-b:a", "192k"]
            }
        }

        args += ["-map_metadata", "0", "-movflags", "+faststart", "-y", "file:" + output.path]
        return args
    }

    /// GIF animado: 15 fps, ancho máx. 640 px, paleta optimizada.
    static func gifArguments(input: URL, output: URL) -> [String] {
        AudioConverter.baseArguments(input: input) + [
            "-vf", "fps=15,scale='min(640,iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle",
            "-loop", "0", "-y", "file:" + output.path,
        ]
    }

    /// Extensión para extraer el audio sin recodificar. `nil` si el códec no tiene un contenedor
    /// de audio razonable (entonces se convierte a WAV).
    static func extractedAudioExtension(codec: String) -> String? {
        switch codec {
        case "aac", "alac": return "m4a"
        case "mp3": return "mp3"
        case "flac": return "flac"
        case "opus": return "opus"
        case "vorbis": return "ogg"
        case "ac3": return "ac3"
        case "eac3": return "eac3"
        case "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_f32le": return "wav"
        default: return nil // pcm big-endian, etc.
        }
    }

    /// AUDIO: copia la primera pista de audio tal cual.
    static func extractAudioArguments(input: URL, output: URL) -> [String] {
        var args = AudioConverter.baseArguments(input: input) + ["-map", "0:a:0", "-vn", "-c:a", "copy", "-map_metadata", "0"]
        if output.pathExtension == "m4a" { args += ["-movflags", "+faststart"] }
        return args + ["-y", "file:" + output.path]
    }

    // MARK: - Herramientas

    /// COMPRESS: H.264 CRF 26, lado corto máx. 1080 px, AAC 128k → MP4.
    static func compressArguments(input: URL, output: URL, hasAudio: Bool, aacAT: Bool) -> [String] {
        var args = AudioConverter.baseArguments(input: input) + [
            "-map", "0:v:0", "-map", "0:a:0?",
            "-c:v", "libx264", "-preset", "medium", "-crf", "26", "-pix_fmt", "yuv420p",
            // Horizontal: alto máx. 1080; vertical: ancho máx. 1080. Siempre pares.
            "-vf", "scale='if(gte(iw,ih),-2,min(1080,trunc(iw/2)*2))':'if(gte(iw,ih),min(1080,trunc(ih/2)*2),-2)'",
        ]
        if hasAudio { args += ["-c:a", aacAT ? "aac_at" : "aac", "-b:a", "128k"] }
        return args + ["-map_metadata", "0", "-movflags", "+faststart", "-y", "file:" + output.path]
    }

    /// MUTE: quita el audio sin recodificar la imagen.
    static func muteArguments(input: URL, output: URL) -> [String] {
        AudioConverter.baseArguments(input: input) + ["-map", "0:v", "-c", "copy", "-an", "-map_metadata", "0",
                                                       "-y", "file:" + output.path]
    }
}
