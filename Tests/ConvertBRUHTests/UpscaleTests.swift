import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ConvertBRUH

/// UPSCALE ×4 con el modelo Real-ESRGAN real (se compila el .mlpackage del repo).
@Suite(.serialized)
struct UpscaleTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-up-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Imagen de prueba: círculo azul sobre fondo rojo o transparente.
    private func makeImage(_ name: String, type: UTType, width: Int, height: Int, transparent: Bool = false,
                           space: CFString = CGColorSpace.sRGB) -> URL {
        let url = dir.appendingPathComponent(name)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: space)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if !transparent {
            ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return url
    }

    private func run(_ url: URL) async throws -> URL {
        try await JobRunner.run(DraggedFile.inspect(url), .tool(.upscale)) { _ in }.url
    }

    private func image(_ url: URL) -> CGImage {
        CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
    }

    /// Alfa de un píxel (x, y desde arriba a la izquierda).
    private func alpha(_ img: CGImage, _ x: Int, _ y: Int) -> UInt8 {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: -x, y: y - img.height + 1, width: img.width, height: img.height))
        return px[3]
    }

    @Test func jpgPorCuatro() async throws {
        // 300 px no es múltiplo del bloque: prueba los bordes
        let src = makeImage("foto.jpg", type: .jpeg, width: 300, height: 200)
        let out = try await run(src)
        #expect(out.lastPathComponent == "foto_upscaled.jpg")
        let img = image(out)
        #expect((img.width, img.height) == (1200, 800))
    }

    @Test func pngConservaTransparenciaYPerfil() async throws {
        let src = makeImage("logo.png", type: .png, width: 120, height: 120, transparent: true, space: CGColorSpace.displayP3)
        let out = try await run(src)
        #expect(out.lastPathComponent == "logo_upscaled.png")
        let img = image(out)
        #expect((img.width, img.height) == (480, 480))
        #expect(alpha(img, 10, 10) == 0)      // esquina transparente
        #expect(alpha(img, 240, 240) == 255)  // centro del círculo opaco
        #expect(img.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func rechazaImagenesGrandes() async throws {
        let src = makeImage("enorme.png", type: .png, width: 2100, height: 10)
        await #expect(throws: (any Error).self) { try await run(src) }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("enorme_upscaled.png").path))
    }
}
