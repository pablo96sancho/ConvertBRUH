import Foundation
import ImageIO
import PDFKit
import Testing
@testable import ConvertBRUH

/// SVG como entrada: ImageIO no lo decodifica, se rasteriza con NSImage.
@Suite(.serialized)
struct SVGTests {
    let dir: URL
    let svg: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-svg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        svg = dir.appendingPathComponent("logo.svg")
        try """
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 12 8">\
        <circle cx="6" cy="4" r="3" fill="blue"/></svg>
        """.write(to: svg, atomically: true, encoding: .utf8)
    }

    private func run(_ op: SliceOperation) async throws -> URL {
        try await JobRunner.run(DraggedFile.inspect(svg), op) { _ in }.url
    }

    private func pixelSize(_ url: URL) -> (Int, Int) {
        let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil) as! [CFString: Any]
        return (props[kCGImagePropertyPixelWidth] as! Int, props[kCGImagePropertyPixelHeight] as! Int)
    }

    @Test func clasificacionYPorciones() {
        let file = DraggedFile.inspect(svg)
        #expect(file.kind == .image)
        #expect(TargetFormat.available(for: [file]) == [.jpg, .png, .webp, .pdf])
    }

    @Test func aPNGConTransparencia() async throws {
        let out = try await run(.convert(.png))
        #expect(out.lastPathComponent == "logo.png")
        #expect(pixelSize(out) == (2048, 1365))
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(out as CFURL, nil)!, 0, nil)!
        #expect(ImageConverter.hasAlpha(image))
    }

    @Test func aJPG() async throws {
        let out = try await run(.convert(.jpg))
        #expect(pixelSize(out) == (2048, 1365))
    }

    @Test func aPDFConservaTamañoIntrinseco() async throws {
        let out = try await run(.convert(.pdf))
        let box = try #require(PDFDocument(url: out)?.page(at: 0)?.bounds(for: .mediaBox))
        #expect(abs(box.width - 120) < 0.5 && abs(box.height - 80) < 0.5)
    }

    @Test func compressLimitaA2560() async throws {
        let big = dir.appendingPathComponent("grande.svg")
        try #"<svg xmlns="http://www.w3.org/2000/svg" width="3000" height="1000"><rect width="3000" height="1000" fill="red"/></svg>"#
            .write(to: big, atomically: true, encoding: .utf8)
        let out = try await JobRunner.run(DraggedFile.inspect(big), .tool(.compress)) { _ in }.url
        #expect(pixelSize(out).0 == 2560)
    }
}
