import Foundation

/// Nombres de salida (§4). Puro: no toca disco.
enum OutputNaming {
    /// `index` 0 → `beat.mp3`; 1 → `beat (1).mp3`. Sin extensión (carpetas) → `beat (1)`.
    static func fileName(base: String, ext: String, index: Int) -> String {
        let name = index == 0 ? base : "\(base) (\(index))"
        return ext.isEmpty ? name : "\(name).\(ext)"
    }

    /// Primer nombre libre en `dir`.
    static func resolve(in dir: URL, base: String, ext: String, exists: (URL) -> Bool) -> URL {
        var index = 0
        while true {
            let candidate = dir.appendingPathComponent(fileName(base: base, ext: ext, index: index))
            if !exists(candidate) { return candidate }
            index += 1
        }
    }

    /// Nombre base de un archivo de salida: el del original más el sufijo de la herramienta.
    static func baseName(for source: URL, suffix: String = "") -> String {
        source.deletingPathExtension().lastPathComponent + suffix
    }
}

/// Dónde y cómo se escribe cada salida.
enum OutputWriter {
    struct Plan: Equatable {
        let directory: URL
        /// `true` si la carpeta del original no admite escritura y se usa Descargas.
        let usedFallback: Bool
    }

    static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    static func isWritableDirectory(_ dir: URL) -> Bool {
        let values = try? dir.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        if values?.volumeIsReadOnly == true { return false }
        return FileManager.default.isWritableFile(atPath: dir.path)
    }

    static func plan(for source: URL) -> Plan {
        let dir = source.deletingLastPathComponent()
        if isWritableDirectory(dir) { return Plan(directory: dir, usedFallback: false) }
        return Plan(directory: downloadsDirectory, usedFallback: true)
    }

    /// Directorio temporal en el mismo volumen que `dir` (para que el move final sea atómico).
    static func makeTemporaryDirectory(near dir: URL) throws -> URL {
        let fm = FileManager.default
        let base: URL
        if let replacement = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: dir, create: true) {
            base = replacement
        } else {
            base = fm.temporaryDirectory
        }
        let tmp = base.appendingPathComponent("ConvertBRUH-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    /// Mueve el temporal terminado a su nombre final, resuelto justo ahora.
    /// Si otro proceso ocupa el nombre entre medias, prueba el siguiente.
    static func commit(_ temp: URL, into dir: URL, base: String, ext: String) throws -> URL {
        let fm = FileManager.default
        for _ in 0..<50 {
            let final = OutputNaming.resolve(in: dir, base: base, ext: ext) { fm.fileExists(atPath: $0.path) }
            do {
                try fm.moveItem(at: temp, to: final)
                return final
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// ¿El error es de permisos? (para reintentar en Descargas)
    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileWriteNoPermissionError || ns.code == NSFileWriteVolumeReadOnlyError) { return true }
        if ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EPERM) || ns.code == Int(EACCES) || ns.code == Int(EROFS)) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isPermissionError(underlying) }
        return false
    }
}
