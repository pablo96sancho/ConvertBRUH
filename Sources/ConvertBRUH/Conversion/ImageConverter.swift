import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Conversión de imágenes con ImageIO (§5.2).
enum ImageConverter {
    struct ImageError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Imagen ya orientada (EXIF aplicado), a tamaño completo o limitada a `maxPixelSize`,
    /// junto con las propiedades del original.
    struct Loaded {
        var image: CGImage
        var properties: [CFString: Any]
        var sourceType: CFString?
    }

    static func load(_ url: URL, maxPixelSize: Int? = nil) throws -> Loaded {
        if (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .svg) == true {
            return try loadSVG(url, maxPixelSize: maxPixelSize)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
            throw ImageError(message: "No se puede leer la imagen")
        }
        let props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let full = max(w, h)
        let limit = min(maxPixelSize ?? full, full)
        // Miniatura "a tamaño completo" para aplicar la orientación sin reducir
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(limit, 1),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ImageError(message: "No se puede decodificar la imagen")
        }
        return Loaded(image: image, properties: props, sourceType: CGImageSourceGetType(src))
    }

    /// ImageIO no decodifica SVG: se rasteriza con NSImage. Lado mayor de al menos 2048 px
    /// (o el doble del tamaño intrínseco), limitado por `maxPixelSize`. El DPI se ajusta
    /// para que el PDF resultante conserve el tamaño intrínseco en puntos.
    static func loadSVG(_ url: URL, maxPixelSize: Int?) throws -> Loaded {
        guard let svg = NSImage(contentsOf: url), svg.size.width > 0, svg.size.height > 0 else {
            throw ImageError(message: "No se puede leer el SVG")
        }
        let side = max(svg.size.width, svg.size.height)
        var target = max(side * 2, 2048)
        if let maxPixelSize { target = min(target, CGFloat(maxPixelSize)) }
        let scale = target / side
        let width = max(Int((svg.size.width * scale).rounded()), 1)
        let height = max(Int((svg.size.height * scale).rounded()), 1)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ImageError(message: "No se pudo preparar la imagen")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        svg.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { throw ImageError(message: "No se puede decodificar el SVG") }
        let dpi = 72 * Double(width) / svg.size.width
        return Loaded(image: image, properties: [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi],
                      sourceType: UTType.svg.identifier as CFString)
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    /// Propiedades a escribir: las del original con la orientación ya aplicada.
    static func outputProperties(from props: [CFString: Any], keepEXIFAndGPS: Bool) -> [CFString: Any] {
        var out: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        for key in [kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            if let v = props[key] { out[key] = v }
        }
        if keepEXIFAndGPS {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
                if let v = props[key] { out[key] = v }
            }
            if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                out[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        return out
    }

    /// Aplana la transparencia sobre blanco (para JPG).
    static func flattenOnWhite(_ image: CGImage) throws -> CGImage {
        let space: CGColorSpace = {
            if let cs = image.colorSpace, cs.model == .rgb { return cs }
            return CGColorSpace(name: CGColorSpace.sRGB)!
        }()
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ImageError(message: "No se pudo preparar la imagen")
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(image, in: rect)
        guard let flat = ctx.makeImage() else { throw ImageError(message: "No se pudo preparar la imagen") }
        return flat
    }

    /// Convierte a sRGB de 8 bits conservando la transparencia. ffmpeg ignora el perfil ICC,
    /// así que una foto en Display P3 saldría desaturada en WebP si no se convierte antes.
    static func convertToSRGB(_ image: CGImage) throws -> CGImage {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ImageError(message: "No se pudo preparar la imagen")
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let converted = ctx.makeImage() else { throw ImageError(message: "No se pudo preparar la imagen") }
        return converted
    }

    /// Argumentos de libwebp: sin pérdida para gráficos con transparencia de un formato sin pérdida
    /// (logos, capturas); con pérdida a calidad 90 para el resto.
    static func webpArguments(input: URL, output: URL, lossless: Bool) -> [String] {
        ["-hide_banner", "-nostdin", "-loglevel", "error", "-i", "file:" + input.path, "-c:v", "libwebp"]
            + (lossless ? ["-lossless", "1"] : ["-quality", "90"])
            + ["-compression_level", "6", "-frames:v", "1", "-y", "file:" + output.path]
    }

    static func isLosslessSource(_ type: CFString?) -> Bool {
        guard let type, let ut = UTType(type as String) else { return false }
        return [UTType.png, .gif, .tiff, .bmp, .svg].contains { ut.conforms(to: $0) }
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, properties: [CFString: Any]) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ImageError(message: "No se puede escribir \(type.preferredFilenameExtension?.uppercased() ?? "la imagen")")
        }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageError(message: "Error al escribir la imagen") }
    }

    static func writeJPEG(_ loaded: Loaded, to url: URL, quality: Double, keepMetadata: Bool) throws {
        let image = hasAlpha(loaded.image) ? try flattenOnWhite(loaded.image) : loaded.image
        var props = outputProperties(from: loaded.properties, keepEXIFAndGPS: keepMetadata)
        props[kCGImageDestinationLossyCompressionQuality] = quality
        try write(image, to: url, type: .jpeg, properties: props)
    }

    static func writePDF(_ loaded: Loaded, to url: URL) throws {
        let dpi = (loaded.properties[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
        var box = CGRect(x: 0, y: 0, width: Double(loaded.image.width) * 72 / dpi, height: Double(loaded.image.height) * 72 / dpi)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ImageError(message: "No se pudo crear el PDF")
        }
        ctx.beginPDFPage(nil)
        ctx.draw(loaded.image, in: box)
        ctx.endPDFPage()
        ctx.closePDF()
    }

    /// Convierte `input` a `target` escribiendo en `output` (temporal).
    static func convert(input: URL, to target: TargetFormat, output: URL) async throws {
        let loaded = try load(input)
        switch target {
        case .jpg:
            try writeJPEG(loaded, to: output, quality: 0.9, keepMetadata: true)
        case .png:
            try write(loaded.image, to: output, type: .png, properties: outputProperties(from: loaded.properties, keepEXIFAndGPS: false))
        case .pdf:
            try writePDF(loaded, to: output)
        case .webp:
            // ImageIO no escribe WebP (Paso 0): PNG temporal → ffmpeg libwebp
            let png = output.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".png")
            defer { try? FileManager.default.removeItem(at: png) }
            try write(convertToSRGB(loaded.image), to: png, type: .png,
                      properties: outputProperties(from: loaded.properties, keepEXIFAndGPS: false))
            let lossless = hasAlpha(loaded.image) && isLosslessSource(loaded.sourceType)
            let result = try await FFmpegRunner.run(executable: Binaries.ffmpeg,
                                                    arguments: webpArguments(input: png, output: output, lossless: lossless))
            guard result.status == 0 else { throw ImageError(message: FFmpegRunner.summarize(result.stderr)) }
        default:
            throw ImageError(message: "Formato no soportado")
        }
    }
}
