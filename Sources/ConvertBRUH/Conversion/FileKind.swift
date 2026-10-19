import Foundation
import UniformTypeIdentifiers

/// Tipo de archivo a efectos de los anillos.
enum FileKind: Equatable {
    case audio
    case video
    case image
    case other

    /// Clasifica por `UTType`. El orden importa: un `.audio` también conforma a `.audiovisualContent`.
    static func classify(_ type: UTType?, isDirectory: Bool) -> FileKind {
        guard !isDirectory, let type else { return .other }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) { return .video }
        if type.conforms(to: .image) { return .image }
        return .other
    }

    static func classify(_ url: URL) -> FileKind {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey])
        return classify(values?.contentType, isDirectory: values?.isDirectory ?? false)
    }
}

/// Un archivo arrastrado ya clasificado.
struct DraggedFile: Equatable {
    let url: URL
    let kind: FileKind
    /// Solo para vídeos: si tiene pista de audio. `nil` si no se ha comprobado.
    var videoHasAudio: Bool?

    /// Formato de salida equivalente al formato de origen (para ocultar su porción).
    var sourceFormat: TargetFormat? { TargetFormat(fileExtension: url.pathExtension) }

    /// Audio o vídeo con audio: lo que entienden ffmpeg y las herramientas de audio.
    var hasUsableAudio: Bool {
        kind == .audio || (kind == .video && videoHasAudio == true)
    }
}
