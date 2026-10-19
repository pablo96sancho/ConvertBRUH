// Genera el icono plantilla de la barra de menú a partir de ICON APP/recovery-convert-svgrepo-com.png.
// Las plantillas solo usan el alfa: la luminosidad se pasa a alfa para conservar los dos tonos
// (flechas opacas, cuadrados semitransparentes).
// Uso: swift scripts/make-menubar-icon.swift <entrada.png> <carpeta-salida>
import CoreGraphics
import Foundation
import ImageIO

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])

let src = CGImageSourceCreateWithURL(input as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(src, 0, nil)!

func render(points: Int, scale: Int, name: String) {
    let px = points * scale
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    for i in stride(from: 0, to: px * px * 4, by: 4) {
        let a = Double(data[i + 3]) / 255
        guard a > 0 else { continue }
        // Desmultiplicar y calcular luminosidad
        let r = Double(data[i]) / 255 / a, g = Double(data[i + 1]) / 255 / a, b = Double(data[i + 2]) / 255 / a
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        // Oscuro (~0,18) → 1; gris (~0,67) → ~0,4
        let alpha = a * min(1, max(0, (1 - lum) / 0.82))
        let v = UInt8((alpha * 255).rounded())
        data[i] = 0; data[i + 1] = 0; data[i + 2] = 0; data[i + 3] = v
    }
    let out = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
    CGImageDestinationFinalize(dest)
    print("✅ \(out.path) (\(px)px)")
}

render(points: 18, scale: 1, name: "MenuBarIcon.png")
render(points: 18, scale: 2, name: "MenuBarIcon@2x.png")
