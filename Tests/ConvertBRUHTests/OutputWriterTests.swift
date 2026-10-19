import Foundation
import Testing
@testable import ConvertBRUH

@Suite struct OutputNamingTests {
    @Test func nombresConIndice() {
        #expect(OutputNaming.fileName(base: "beat", ext: "mp3", index: 0) == "beat.mp3")
        #expect(OutputNaming.fileName(base: "beat", ext: "mp3", index: 2) == "beat (2).mp3")
        #expect(OutputNaming.fileName(base: "Carpeta", ext: "", index: 1) == "Carpeta (1)")
    }

    @Test func resuelvePrimerLibre() {
        let dir = URL(fileURLWithPath: "/tmp/x")
        let ocupados: Set<String> = ["beat.mp3", "beat (1).mp3"]
        let url = OutputNaming.resolve(in: dir, base: "beat", ext: "mp3") { ocupados.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "beat (2).mp3")
    }

    @Test func baseConSufijoYCaracteresRaros() {
        let src = URL(fileURLWithPath: "/a/@Placement Chasers: Hi Hat 🔥.wav")
        #expect(OutputNaming.baseName(for: src) == "@Placement Chasers: Hi Hat 🔥")
        #expect(OutputNaming.baseName(for: src, suffix: "_normalized") == "@Placement Chasers: Hi Hat 🔥_normalized")
    }

    @Test func commitNoSobrescribe() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("cb-test-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try "original".write(to: dir.appendingPathComponent("beat.mp3"), atomically: true, encoding: .utf8)

        let tmpDir = try OutputWriter.makeTemporaryDirectory(near: dir)
        defer { try? fm.removeItem(at: tmpDir) }
        let tmp = tmpDir.appendingPathComponent("salida.mp3")
        try "nuevo".write(to: tmp, atomically: true, encoding: .utf8)

        let final = try OutputWriter.commit(tmp, into: dir, base: "beat", ext: "mp3")
        #expect(final.lastPathComponent == "beat (1).mp3")
        #expect(try String(contentsOf: dir.appendingPathComponent("beat.mp3"), encoding: .utf8) == "original")
        #expect(!fm.fileExists(atPath: tmp.path))
    }

    @Test func detectaErroresDePermiso() {
        #expect(OutputWriter.isPermissionError(CocoaError(.fileWriteNoPermission)))
        #expect(OutputWriter.isPermissionError(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
        #expect(!OutputWriter.isPermissionError(CocoaError(.fileNoSuchFile)))
    }
}
