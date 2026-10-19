import Foundation

/// Formatos de salida del anillo Convertir.
enum TargetFormat: String, CaseIterable, Equatable {
    case mp3, wav, m4a, flac, aiff
    case jpg, png, webp, pdf
    case mp4, mov, gif
    /// Extrae la pista de audio tal cual, sin recodificar (la extensión depende del códec).
    case extractAudio = "audio"

    static let audio: [TargetFormat] = [.mp3, .wav, .m4a, .flac, .aiff]
    static let image: [TargetFormat] = [.jpg, .png, .webp, .pdf]
    /// Vídeo con pista de audio (orden horario desde arriba).
    static let video: [TargetFormat] = [.mp4, .mov, .gif, .extractAudio, .mp3, .wav]
    /// Vídeo sin pista de audio.
    static let silentVideo: [TargetFormat] = [.mp4, .mov, .gif]

    var label: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }

    /// Salidas de audio que pasan por `AudioConverter`.
    var isAudio: Bool { TargetFormat.audio.contains(self) }
    /// Salidas de vídeo que pasan por `VideoConverter`.
    var isVideo: Bool { self == .mp4 || self == .mov || self == .gif }

    /// Reconoce una extensión de archivo (con alias) como uno de los formatos de salida.
    init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "mp3": self = .mp3
        case "wav", "wave": self = .wav
        case "m4a": self = .m4a
        case "flac": self = .flac
        case "aif", "aiff", "aifc": self = .aiff
        case "jpg", "jpeg": self = .jpg
        case "png": self = .png
        case "webp": self = .webp
        case "pdf": self = .pdf
        case "mp4": self = .mp4
        case "mov": self = .mov
        default: return nil
        }
    }

    /// Formatos válidos para un archivo concreto.
    static func targets(for file: DraggedFile) -> [TargetFormat] {
        switch file.kind {
        case .audio: return audio
        case .image: return image
        case .video: return file.videoHasAudio == false ? silentVideo : video
        case .other: return []
        }
    }

    /// Porciones del anillo Convertir para un conjunto de archivos (§3.5).
    /// Solo las válidas para todos los convertibles, en el orden del primero.
    static func available(for files: [DraggedFile]) -> [TargetFormat] {
        let usable = files.filter { !targets(for: $0).isEmpty }
        guard let first = usable.first else { return [] }
        let sets = usable.map { Set(targets(for: $0)) }
        var result = targets(for: first).filter { t in sets.allSatisfy { $0.contains(t) } }

        // Se oculta el formato de origen si todos lo comparten
        let sources = Set(usable.map(\.sourceFormat))
        if sources.count == 1, let only = sources.first, let only {
            result.removeAll { $0 == only }
        }
        return result
    }
}
