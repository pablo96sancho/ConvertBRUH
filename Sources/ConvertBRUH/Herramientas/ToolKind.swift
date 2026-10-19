import Foundation

/// Herramientas automáticas del anillo Shift+Option (§3.7).
enum ToolKind: String, CaseIterable, Equatable {
    // Orden horario desde arriba
    case normalize, compress, channels, mute, metadata

    var label: String { rawValue.uppercased() }

    var symbol: String {
        switch self {
        case .normalize: "waveform"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .channels: "hifispeaker.2"
        case .mute: "speaker.slash"
        case .metadata: "tag"
        }
    }

    /// Formatos de imagen a los que se les pueden quitar metadatos sin recodificar.
    static let metadataImageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"]

    func isValid(for file: DraggedFile) -> Bool {
        switch self {
        case .normalize, .channels:
            return file.kind == .audio
        case .compress:
            // Audio → MP3 ligero; imagen → JPG/PNG reducido; vídeo → MP4 1080p
            return file.kind == .audio || file.kind == .image || file.kind == .video
        case .mute:
            return file.kind == .video && file.videoHasAudio == true
        case .metadata:
            if file.kind == .audio { return true }
            if file.kind == .image { return ToolKind.metadataImageExtensions.contains(file.url.pathExtension.lowercased()) }
            return false // en vídeos no: copiar el audio sin tags cambiaría el contenedor
        }
    }

    /// Porciones disponibles: las válidas para todos los archivos procesables.
    static func available(for files: [DraggedFile]) -> [ToolKind] {
        let usable = files.filter { $0.kind != .other }
        guard !usable.isEmpty else { return [] }
        return allCases.filter { tool in usable.allSatisfy { tool.isValid(for: $0) } }
    }
}
