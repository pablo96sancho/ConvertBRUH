import AppKit

/// Acciones del anillo Option (§3.6).
@MainActor
final class FileActions {
    private var floats: [FloatPanel] = []

    func copy(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        Log.acciones.info("Copiados \(urls.count) archivo(s) al portapapeles")
    }

    func copyPath(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        Log.acciones.info("Copiadas \(urls.count) ruta(s)")
    }

    func airDrop(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        // El selector de AirDrop es una ventana de nuestra app: hay que activarla para que salga delante
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    func float(_ urls: [URL]) {
        let offset = CGFloat(floats.count % 6) * 24
        let panel = FloatPanel(urls: urls) { [weak self] closed in
            self?.floats.removeAll { $0 === closed }
        }
        let p = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: p.x + 40 + offset, y: p.y - panel.frame.height / 2 - offset)
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), vf.maxX - panel.frame.width)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - panel.frame.height)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        floats.append(panel)
    }

    /// Pide carpeta y mueve los archivos ahí. `completion` recibe el mensaje de error, si lo hay.
    func move(_ urls: [URL], completion: @escaping (String?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Mover aquí"
        panel.message = urls.count == 1 ? "Mover «\(urls[0].lastPathComponent)» a…" : "Mover \(urls.count) ítems a…"
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return completion(nil) }
            var moved: [URL] = []
            var errors: [String] = []
            for url in urls {
                do {
                    if let final = try Self.move(url, into: dest) { moved.append(final) }
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if !moved.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(moved) }
            completion(errors.isEmpty ? nil : "Move: " + errors.joined(separator: " · "))
        }
    }

    /// Mueve con la regla de colisiones de §4. Devuelve `nil` si ya estaba en esa carpeta.
    nonisolated static func move(_ url: URL, into dir: URL) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw JobError("El archivo ya no existe") }
        if url.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL { return nil }

        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let base = isDir ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let ext = isDir ? "" : url.pathExtension

        let sameVolume: Bool = {
            let a = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
            let b = try? dir.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
            return a != nil && a == b
        }()

        for _ in 0..<50 {
            let final = OutputNaming.resolve(in: dir, base: base, ext: ext) { fm.fileExists(atPath: $0.path) }
            do {
                if sameVolume {
                    try fm.moveItem(at: url, to: final)
                } else {
                    // Otro volumen: copiar y borrar el original solo si la copia terminó bien
                    try fm.copyItem(at: url, to: final)
                    try fm.removeItem(at: url)
                }
                return final
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
