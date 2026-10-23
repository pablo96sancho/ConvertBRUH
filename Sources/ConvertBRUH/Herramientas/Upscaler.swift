import CoreGraphics
import CoreML
import Foundation

/// Super-resolución ×4 con Real-ESRGAN (realesr-general-x4v3) en Core ML, por bloques.
/// Es un actor: el modelo se carga una vez y los upscales van de uno en uno (cada salida
/// puede ocupar cientos de MB).
actor Upscaler {
    static let shared = Upscaler()

    static let scale = 4
    /// Tamaño fijo del bloque de entrada del modelo (`scripts/convert-upscale-model.py`).
    static let tile = 256
    /// Margen de cada bloque que se descarta al pegar, para que no se noten las costuras.
    static let pad = 16
    /// Lado mayor máximo de la entrada: 2048 → 8192 px.
    static let maxInputPixelSize = 2048

    private var model: MLModel?

    /// Modelo compilado dentro del .app; en desarrollo (`swift test`) se compila el .mlpackage del repo.
    private func loadModel() async throws -> MLModel {
        if let model { return model }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        let compiled: URL
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Models/RealESRGAN.mlmodelc"),
           FileManager.default.fileExists(atPath: bundled.path) {
            compiled = bundled
        } else {
            let package = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/Models/RealESRGAN.mlpackage")
            compiled = try await MLModel.compileModel(at: package)
        }
        let loaded = try MLModel(contentsOf: compiled, configuration: config)
        model = loaded
        return loaded
    }

    /// Amplía `image` ×4 conservando su espacio de color. La transparencia no pasa por el modelo:
    /// se amplía aparte con interpolación de alta calidad.
    func upscale(_ image: CGImage, progress: @Sendable (Double) -> Void) async throws -> CGImage {
        let model = try await loadModel()
        let tile = Self.tile, pad = Self.pad, scale = Self.scale
        let step = tile - 2 * pad
        let w = image.width, h = image.height, ow = w * scale, oh = h * scale
        let space: CGColorSpace = {
            if let cs = image.colorSpace, cs.model == .rgb { return cs }
            return CGColorSpace(name: CGColorSpace.sRGB)!
        }()
        let alpha = ImageConverter.hasAlpha(image)

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        try rgba.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ImageConverter.ImageError(message: "No se pudo preparar la imagen")
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        // Canal alfa ampliado (255 si la imagen es opaca)
        var outAlpha = [UInt8](repeating: 255, count: alpha ? ow * oh : 0)
        if alpha {
            // El alfa como imagen en grises, ampliada con interpolación de alta calidad
            let gray = CGColorSpaceCreateDeviceGray()
            let alphaPlane = Data(stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] })
            guard let provider = CGDataProvider(data: alphaPlane as CFData),
                  let mask = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: gray,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
                                     decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
                throw ImageConverter.ImageError(message: "No se pudo preparar la imagen")
            }
            try outAlpha.withUnsafeMutableBytes { buf in
                guard let ctx = CGContext(data: buf.baseAddress, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: ow,
                                          space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                    throw ImageConverter.ImageError(message: "No se pudo preparar la imagen")
                }
                ctx.interpolationQuality = .high
                ctx.draw(mask, in: CGRect(x: 0, y: 0, width: ow, height: oh))
            }
        }

        var out = [UInt8](repeating: 255, count: ow * oh * 4)
        let input = try MLMultiArray(shape: [1, 3, NSNumber(value: tile), NSNumber(value: tile)], dataType: .float16)
        let plane = tile * tile, ot = tile * scale, oplane = ot * ot
        let cols = (w + step - 1) / step, rows = (h + step - 1) / step
        var done = 0

        for ty in stride(from: 0, to: h, by: step) {
            for tx in stride(from: 0, to: w, by: step) {
                try Task.checkCancellation()
                // Bloque con margen; fuera de la imagen se repite el borde. RGB sin premultiplicar en [0, 1]
                let ip = input.dataPointer.bindMemory(to: Float16.self, capacity: 3 * plane)
                for y in 0..<tile {
                    let sy = min(max(ty - pad + y, 0), h - 1)
                    for x in 0..<tile {
                        let sx = min(max(tx - pad + x, 0), w - 1)
                        let i = (sy * w + sx) * 4
                        let a = Float(rgba[i + 3])
                        let k: Float = a > 0 ? 1 / a : 0
                        ip[y * tile + x] = Float16(Float(rgba[i]) * k)
                        ip[plane + y * tile + x] = Float16(Float(rgba[i + 1]) * k)
                        ip[2 * plane + y * tile + x] = Float16(Float(rgba[i + 2]) * k)
                    }
                }
                let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input": input]))
                guard let o = result.featureValue(for: "output")?.multiArrayValue else {
                    throw ImageConverter.ImageError(message: "El modelo de UPSCALE no devolvió nada")
                }
                let op = o.dataPointer.bindMemory(to: Float16.self, capacity: 3 * oplane)
                // Solo la parte central del bloque, premultiplicada por el alfa ampliado
                let cw = min(step, w - tx) * scale, ch = min(step, h - ty) * scale
                for y in 0..<ch {
                    for x in 0..<cw {
                        let si = (pad * scale + y) * ot + pad * scale + x
                        let oy = ty * scale + y, ox = tx * scale + x
                        let di = (oy * ow + ox) * 4
                        let a: Float = alpha ? Float(outAlpha[oy * ow + ox]) : 255
                        out[di] = UInt8(min(max(Float(op[si]) * a + 0.5, 0), 255))
                        out[di + 1] = UInt8(min(max(Float(op[oplane + si]) * a + 0.5, 0), 255))
                        out[di + 2] = UInt8(min(max(Float(op[2 * oplane + si]) * a + 0.5, 0), 255))
                        out[di + 3] = UInt8(a)
                    }
                }
                done += 1
                progress(Double(done) / Double(cols * rows))
            }
        }

        let info = alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let result = CGImage(width: ow, height: oh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: ow * 4,
                                   space: space, bitmapInfo: CGBitmapInfo(rawValue: info.rawValue), provider: provider,
                                   decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw ImageConverter.ImageError(message: "No se pudo crear la imagen ampliada")
        }
        return result
    }
}
