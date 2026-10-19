import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Herramientas de imagen (§3.7).
enum ImageTools {
    static let compressMaxPixelSize = 2560

    /// Extensión de salida de COMPRESS: JPG sin transparencia, PNG con ella.
    static func compressOutputExtension(hasAlpha: Bool) -> String { hasAlpha ? "png" : "jpg" }

    /// COMPRESS. Devuelve la extensión con la que hay que guardar el resultado.
    static func compress(input: URL, output: URL) throws -> String {
        let loaded = try ImageConverter.load(input, maxPixelSize: compressMaxPixelSize)
        if ImageConverter.hasAlpha(loaded.image) {
            try ImageConverter.write(loaded.image, to: output, type: .png,
                                     properties: ImageConverter.outputProperties(from: loaded.properties, keepEXIFAndGPS: false))
            return "png"
        }
        try ImageConverter.writeJPEG(loaded, to: output, quality: 0.7, keepMetadata: false)
        return "jpg"
    }

    /// METADATA: quita EXIF, GPS, IPTC y XMP sin recodificar; conserva la orientación (Paso 0, punto 10).
    static func stripMetadata(input: URL, output: URL) throws {
        guard let src = CGImageSourceCreateWithURL(input as CFURL, nil), let type = CGImageSourceGetType(src),
              let dest = CGImageDestinationCreateWithURL(output as CFURL, type, 1, nil) else {
            throw ImageConverter.ImageError(message: "No se puede leer la imagen")
        }
        let props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        let meta = CGImageMetadataCreateMutable()
        if let orientation = props[kCGImagePropertyOrientation] as? Int {
            CGImageMetadataSetValueMatchingImageProperty(meta, kCGImagePropertyTIFFDictionary,
                                                         kCGImagePropertyTIFFOrientation, orientation as CFNumber)
        }
        let opts: [CFString: Any] = [
            kCGImageDestinationMetadata: meta,
            kCGImageDestinationMergeMetadata: false,
            kCGImageMetadataShouldExcludeXMP: true,
            kCGImageMetadataShouldExcludeGPS: true,
        ]
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dest, src, opts as CFDictionary, &error) else {
            let message = (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String } ?? "error desconocido"
            throw ImageConverter.ImageError(message: "No se pudieron quitar los metadatos: \(message)")
        }
    }
}
