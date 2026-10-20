import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ConvertBRUH

private func file(_ name: String, _ kind: FileKind, videoAudio: Bool? = nil) -> DraggedFile {
    DraggedFile(url: URL(fileURLWithPath: "/x/\(name)"), kind: kind, videoHasAudio: videoAudio)
}

@Suite struct ClasificacionTests {
    @Test func porUTType() {
        #expect(FileKind.classify(.wav, isDirectory: false) == .audio)
        #expect(FileKind.classify(.mpeg4Audio, isDirectory: false) == .audio)
        #expect(FileKind.classify(.quickTimeMovie, isDirectory: false) == .video)
        #expect(FileKind.classify(.heic, isDirectory: false) == .image)
        #expect(FileKind.classify(.plainText, isDirectory: false) == .other)
        #expect(FileKind.classify(.folder, isDirectory: true) == .other)
    }

    @Test func modificadores() {
        #expect(RingKind.from(shift: true, option: false, command: false, control: false) == .convertir)
        #expect(RingKind.from(shift: false, option: true, command: false, control: false) == .acciones)
        #expect(RingKind.from(shift: false, option: false, command: false, control: true) == .herramientas)
        #expect(RingKind.from(shift: true, option: true, command: false, control: false) == nil)
        #expect(RingKind.from(shift: true, option: false, command: false, control: true) == nil)
        #expect(RingKind.from(shift: true, option: false, command: true, control: false) == nil)
        #expect(RingKind.from(shift: false, option: false, command: false, control: false) == nil)
    }
}

@Suite struct PorcionesTests {
    @Test func wavOcultaWAV() {
        #expect(TargetFormat.available(for: [file("beat.wav", .audio)]) == [.mp3, .m4a, .flac, .aiff])
    }

    @Test func heicMuestraTodasLasDeImagen() {
        #expect(TargetFormat.available(for: [file("foto.heic", .image)]) == [.jpg, .png, .webp, .pdf])
    }

    @Test func origenesDistintosNoOcultan() {
        let r = TargetFormat.available(for: [file("a.wav", .audio), file("b.mp3", .audio)])
        #expect(r == TargetFormat.audio)
    }

    @Test func mezclaAudioImagenNoTieneNada() {
        #expect(TargetFormat.available(for: [file("a.wav", .audio), file("b.png", .image)]).isEmpty)
    }

    @Test func noConvertiblesSeIgnoran() {
        let r = TargetFormat.available(for: [file("a.png", .image), file("notas.txt", .other)])
        #expect(r == [.jpg, .webp, .pdf])
    }

    @Test func video() {
        // Se oculta MOV porque el origen es MOV
        #expect(TargetFormat.available(for: [file("v.mov", .video, videoAudio: true)]) == [.mp4, .gif, .extractAudio, .mp3, .wav])
        #expect(TargetFormat.available(for: [file("v.mp4", .video, videoAudio: true)]).map(\.label) == ["MOV", "GIF", "AUDIO", "MP3", "WAV"])
        // Sin pista de audio: solo formatos de vídeo
        #expect(TargetFormat.available(for: [file("v.mkv", .video, videoAudio: false)]) == [.mp4, .mov, .gif])
    }

    @Test func videoMasAudioSoloComparteMP3yWAV() {
        let r = TargetFormat.available(for: [file("v.mov", .video, videoAudio: true), file("a.flac", .audio)])
        #expect(r == [.mp3, .wav])
    }

    @Test func soloCarpetasNoHayConvertirPeroSiAcciones() {
        let carpeta = file("Carpeta", .other)
        #expect(RingSlice.slices(for: .convertir, files: [carpeta]).isEmpty)
        #expect(RingSlice.slices(for: .acciones, files: [carpeta]).map(\.label) == ["AIRDROP", "FLOAT", "COPY", "MOVE", "COPY PATH"])
    }

    @Test func herramientas() {
        #expect(ToolKind.available(for: [file("a.wav", .audio)]) == [.normalize, .compress, .channels, .metadata])
        #expect(ToolKind.available(for: [file("a.jpg", .image)]) == [.compress, .metadata])
        #expect(ToolKind.available(for: [file("a.gif", .image)]) == [.compress])
        #expect(ToolKind.available(for: [file("v.mov", .video, videoAudio: true)]) == [.compress, .mute])
        #expect(ToolKind.available(for: [file("v.mov", .video, videoAudio: false)]) == [.compress])
        // Mezcla: COMPRESS y METADATA valen para ambos
        #expect(ToolKind.available(for: [file("a.wav", .audio), file("b.png", .image)]) == [.compress, .metadata])
    }

    @Test func pdf() {
        #expect(FileKind.classify(.pdf, isDirectory: false) == .pdf)
        #expect(TargetFormat.available(for: [file("doc.pdf", .pdf)]).map(\.label) == ["TXT", "DOCX", "JPG", "PNG"])
        // Con imágenes solo comparten JPG y PNG
        #expect(TargetFormat.available(for: [file("doc.pdf", .pdf), file("a.heic", .image)]) == [.jpg, .png])
        #expect(ToolKind.available(for: [file("doc.pdf", .pdf)]) == [.metadata])
    }

    @Test func nombresDePagina() {
        #expect(PDFConverter.pageFileName(base: "informe", page: 3, of: 5, ext: "png") == "informe_p3.png")
        #expect(PDFConverter.pageFileName(base: "informe", page: 3, of: 12, ext: "jpg") == "informe_p03.jpg")
        #expect(PDFConverter.pageFileName(base: "informe", page: 100, of: 100, ext: "jpg") == "informe_p100.jpg")
    }
}

@Suite struct GeometriaTests {
    let g = RingGeometry(count: 4)

    @Test func centroYFuera() {
        #expect(g.hit(.zero) == .center)
        #expect(g.hit(CGPoint(x: 0, y: 40)) == .center)
        #expect(g.hit(CGPoint(x: 0, y: 200)) == .outside)
    }

    @Test func primeraArribaYSentidoHorario() {
        #expect(g.hit(CGPoint(x: 0, y: 100)) == .slice(0))     // arriba
        #expect(g.hit(CGPoint(x: 100, y: 0)) == .slice(1))     // derecha
        #expect(g.hit(CGPoint(x: 0, y: -100)) == .slice(2))    // abajo
        #expect(g.hit(CGPoint(x: -100, y: 0)) == .slice(3))    // izquierda
        #expect(g.hit(CGPoint(x: -20, y: 100)) == .slice(0))   // un poco a la izquierda de arriba
    }

    @Test func cincoPorciones() {
        let g5 = RingGeometry(count: 5)
        // 72° por porción; a 60° desde arriba ya es la segunda
        let a = 60.0 * .pi / 180
        #expect(g5.hit(CGPoint(x: 100 * sin(a), y: 100 * cos(a))) == .slice(1))
        let b = 350.0 * .pi / 180
        #expect(g5.hit(CGPoint(x: 100 * sin(b), y: 100 * cos(b))) == .slice(0))
    }
}
