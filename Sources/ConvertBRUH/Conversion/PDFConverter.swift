import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Conversión de PDF con PDFKit (§5.4).
enum PDFConverter {
    /// Resolución a la que se renderizan las páginas a JPG/PNG.
    static let renderDPI = 200.0

    static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw JobError("No se puede leer el PDF") }
        guard !doc.isLocked else { throw JobError("El PDF está protegido con contraseña") }
        guard doc.pageCount > 0 else { throw JobError("El PDF no tiene páginas") }
        return doc
    }

    /// TXT: todo el texto del documento en UTF-8.
    static func writeText(_ doc: PDFDocument, to url: URL) throws {
        let text = doc.string ?? ""
        try requireText(text)
        try Data(text.utf8).write(to: url)
    }

    /// DOCX: texto con fuentes, tamaños y negritas; cada página PDF empieza en una página nueva de Word.
    /// No conserva la maquetación ni las imágenes (Paso 0, punto 12).
    static func writeDOCX(_ doc: PDFDocument, to url: URL) throws {
        let all = NSMutableAttributedString()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i)?.attributedString else { continue }
            // `\f` se escribe como salto de página de Word
            if all.length > 0 { all.append(NSAttributedString(string: "\u{0C}")) }
            all.append(page)
        }
        try requireText(all.string)
        let data = try all.data(from: NSRange(location: 0, length: all.length),
                                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        try data.write(to: url)
    }

    private static func requireText(_ text: String) throws {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw JobError("El PDF no tiene texto (¿es un escaneo?)")
        }
    }

    /// Nombre de cada página: `informe_p1.png`, o `informe_p01.png` si hay 10 o más (para que se ordenen bien).
    static func pageFileName(base: String, page: Int, of count: Int, ext: String) -> String {
        let width = String(count).count
        let number = String(repeating: "0", count: max(width - String(page).count, 0)) + String(page)
        return "\(base)_p\(number).\(ext)"
    }

    /// Página renderizada sobre blanco, con la rotación aplicada, a `renderDPI`.
    static func render(_ page: PDFPage) throws -> CGImage {
        let box = page.bounds(for: .cropBox)
        let rotated = page.rotation % 180 != 0
        let size = rotated ? CGSize(width: box.height, height: box.width) : box.size
        let scale = renderDPI / 72
        let w = max(Int((size.width * scale).rounded()), 1)
        let h = max(Int((size.height * scale).rounded()), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw JobError("La página es demasiado grande")
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        // `draw(with:to:)` aplica la rotación y el origen del cropBox (Paso 0)
        page.draw(with: .cropBox, to: ctx)
        guard let image = ctx.makeImage() else { throw JobError("No se pudo renderizar la página") }
        return image
    }

    /// JPG/PNG: una imagen por página. Con una sola página escribe `output`; con varias, crea la carpeta
    /// `output` con `base_p1.ext`, `base_p2.ext`… Devuelve si el resultado es una carpeta.
    static func writePages(_ doc: PDFDocument, to output: URL, base: String, target: TargetFormat,
                           progress: (Double) -> Void) throws -> Bool {
        let type: UTType = target == .jpg ? .jpeg : .png
        var props: [CFString: Any] = [kCGImagePropertyDPIWidth: renderDPI, kCGImagePropertyDPIHeight: renderDPI]
        if target == .jpg { props[kCGImageDestinationLossyCompressionQuality] = 0.9 }

        let count = doc.pageCount
        let multiple = count > 1
        if multiple { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false) }
        for i in 0..<count {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let page = doc.page(at: i) else { return }
                let url = multiple
                    ? output.appendingPathComponent(pageFileName(base: base, page: i + 1, of: count, ext: target.fileExtension))
                    : output
                try ImageConverter.write(try render(page), to: url, type: type, properties: props)
            }
            progress(Double(i + 1) / Double(count))
        }
        return multiple
    }

    /// METADATA: borra autor, título, creador, productor, fechas y palabras clave. Reescribe el PDF con
    /// PDFKit (las páginas no se rasterizan; el texto sigue siendo seleccionable).
    static func stripMetadata(input: URL, output: URL) throws {
        let doc = try open(input)
        doc.documentAttributes = [:]
        guard doc.write(to: output) else { throw JobError("No se pudo escribir el PDF") }
    }
}
