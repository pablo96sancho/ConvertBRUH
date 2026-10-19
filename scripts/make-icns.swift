// Crea un .iconset a partir del PNG exportado de Icon Composer (1024, a sangre) con el margen
// estándar de los iconos de macOS (contenido de 824 px en un lienzo de 1024).
// Uso: swift scripts/make-icns.swift <entrada-1024.png> <salida.iconset>
import CoreGraphics
import Foundation
import ImageIO

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(input as CFURL, nil)!, 0, nil)!

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = points * scale
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        let content = CGFloat(px) * 824 / 1024
        let inset = (CGFloat(px) - content) / 2
        ctx.draw(image, in: CGRect(x: inset, y: inset, width: content, height: content))
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let dest = CGImageDestinationCreateWithURL(iconset.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
    }
}
print("✅ \(iconset.path)")
