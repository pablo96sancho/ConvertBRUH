import AppKit
import SwiftUI
import Testing
@testable import ConvertBRUH

/// Genera la portada del README con el `RingView` real.
/// Solo se ejecuta a propósito: `COVER_OUTPUT=cover.jpg swift test --filter CoverRender`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["COVER_OUTPUT"] != nil))
struct CoverRender {
    @MainActor
    private func ring(_ kind: RingKind, _ files: [DraggedFile], size: String, hovered: Int?) -> RingModel {
        let m = RingModel()
        m.kind = kind
        m.slices = RingSlice.slices(for: kind, files: files)
        m.sizeText = size
        m.hovered = hovered
        return m
    }

    @Test @MainActor func render() throws {
        let wav = DraggedFile(url: URL(fileURLWithPath: "/x/beat.wav"), kind: .audio)
        let rings: [(String, String, RingModel)] = [
            ("Shift", "Convertir", ring(.convertir, [wav], size: "84 KB", hovered: 0)),
            ("Option", "Acciones", ring(.acciones, [wav], size: "84 KB", hovered: 1)),
            ("Control", "Herramientas", ring(.herramientas, [wav], size: "84 KB", hovered: 0)),
        ]

        let view = ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.09), Color(red: 0.02, green: 0.03, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 34) {
                VStack(spacing: 8) {
                    Text("ConvertBRUH")
                        .font(.system(size: 54, weight: .heavy))
                    Text("Arrastra un archivo y mantén una tecla")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .foregroundStyle(.white)
                HStack(spacing: 56) {
                    ForEach(rings, id: \.0) { key, name, model in
                        VStack(spacing: 18) {
                            RingView(model: model)
                                .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
                            HStack(spacing: 10) {
                                Text(key)
                                    .font(.system(size: 17, weight: .heavy))
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.16)))
                                Text(name).font(.system(size: 19, weight: .bold))
                            }
                            .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .frame(width: 1200, height: 640)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let jpg = try #require(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]))
        try jpg.write(to: URL(fileURLWithPath: ProcessInfo.processInfo.environment["COVER_OUTPUT"]!))
    }
}
