import AppKit
import CoreText
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import ConvertBRUH

/// PDF → TXT, DOCX, JPG, PNG y METADATA con PDFKit real (no necesita ffmpeg).
@Suite(.serialized)
struct PDFTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// PDF A4 con `pages` páginas de texto (título en negrita) y autor en los metadatos.
    /// Sin texto si `text` es false (como un escaneo).
    private func makePDF(_ name: String, pages: Int, text: Bool = true) -> URL {
        let url = dir.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let info: [CFString: Any] = [kCGPDFContextAuthor: "Autor Secreto", kCGPDFContextTitle: "Título"]
        let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary)!
        for n in 1...pages {
            ctx.beginPDFPage(nil)
            if text {
                let s = NSMutableAttributedString(string: "Página \(n)\n", attributes: [.font: NSFont(name: "Helvetica-Bold", size: 20)!])
                s.append(NSAttributedString(string: "Acentos ñ á é.", attributes: [.font: NSFont(name: "Helvetica", size: 12)!]))
                let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(s), CFRange(location: 0, length: 0),
                                                     CGPath(rect: box.insetBy(dx: 50, dy: 50), transform: nil), nil)
                CTFrameDraw(frame, ctx)
            } else {
                ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
                ctx.fill(CGRect(x: 100, y: 100, width: 50, height: 50))
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    private func run(_ url: URL, _ op: SliceOperation) async throws -> URL {
        try await JobRunner.run(DraggedFile.inspect(url), op) { _ in }.url
    }

    @Test func clasificacion() {
        let src = makePDF("doc.pdf", pages: 1)
        #expect(DraggedFile.inspect(src).kind == .pdf)
    }

    @Test func texto() async throws {
        let txt = try await run(makePDF("informe.pdf", pages: 2), .convert(.txt))
        #expect(txt.lastPathComponent == "informe.txt")
        let s = try String(contentsOf: txt, encoding: .utf8)
        #expect(s.contains("Página 1") && s.contains("Página 2") && s.contains("ñ á é"))
    }

    @Test func docx() async throws {
        let out = try await run(makePDF("informe.pdf", pages: 2), .convert(.docx))
        #expect(out.lastPathComponent == "informe.docx")
        // Se vuelve a leer con el lector de Office de AppKit
        let back = try NSAttributedString(url: out, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                                          documentAttributes: nil)
        #expect(back.string.contains("Página 2"))
        let font = back.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func escaneoSinTexto() async throws {
        let src = makePDF("escaneo.pdf", pages: 1, text: false)
        await #expect(throws: JobError.self) { try await run(src, .convert(.txt)) }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("escaneo.txt").path))
        // Las imágenes sí salen
        #expect(try await run(src, .convert(.png)).lastPathComponent == "escaneo.png")
    }

    @Test func unaPaginaAImagen() async throws {
        let png = try await run(makePDF("hoja.pdf", pages: 1), .convert(.png))
        #expect(png.lastPathComponent == "hoja.png")
        let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(png as CFURL, nil)!, 0, nil) as! [CFString: Any]
        // A4 a 200 DPI
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 1653)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 2339)
    }

    @Test func variasPaginasACarpeta() async throws {
        let src = makePDF("informe.pdf", pages: 3)
        let out = try await run(src, .convert(.jpg))
        #expect(out.lastPathComponent == "informe")
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        #expect(names == ["informe_p1.jpg", "informe_p2.jpg", "informe_p3.jpg"])
        // Repetir → `informe (1)`
        #expect(try await run(src, .convert(.jpg)).lastPathComponent == "informe (1)")
    }

    @Test func metadata() async throws {
        let src = makePDF("privado.pdf", pages: 2)
        let clean = try await run(src, .tool(.metadata))
        #expect(clean.lastPathComponent == "privado_clean.pdf")
        let doc = try #require(PDFDocument(url: clean))
        #expect(doc.documentAttributes?[PDFDocumentAttribute.authorAttribute] == nil)
        #expect(doc.pageCount == 2)
        #expect(doc.string?.contains("Página 2") == true)
        // El original sigue igual
        #expect(PDFDocument(url: src)?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String == "Autor Secreto")
    }
}
