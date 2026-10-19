import Foundation

/// Formatos de salida del anillo Convertir.
enum TargetFormat: String, CaseIterable, Equatable {
    case mp3, wav, m4a, flac, aiff
    case jpg, png, webp, pdf

    static let audio: [TargetFormat] = [.mp3, .wav, .m4a, .flac, .aiff]
    static let image: [TargetFormat] = [.jpg, .png, .webp, .pdf]

    var label: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
    var isAudio: Bool { TargetFormat.audio.contains(self) }

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
        default: return nil
        }
    }

    /// Porciones del anillo Convertir para un conjunto de archivos (§3.5).
    /// Solo cuentan los convertibles; si no hay formatos en común, devuelve vacío.
    static func available(for files: [DraggedFile]) -> [TargetFormat] {
        let usable = files.filter { $0.hasUsableAudio || $0.kind == .image }
        guard !usable.isEmpty else { return [] }

        var result: [TargetFormat]
        if usable.allSatisfy(\.hasUsableAudio) {
            result = audio
        } else if usable.allSatisfy({ $0.kind == .image }) {
            result = image
        } else {
            return [] // audio e imagen mezclados: nada en común
        }

        // Se oculta el formato de origen si todos lo comparten
        let sources = Set(usable.map(\.sourceFormat))
        if sources.count == 1, let only = sources.first, let only {
            result.removeAll { $0 == only }
        }
        return result
    }
}
