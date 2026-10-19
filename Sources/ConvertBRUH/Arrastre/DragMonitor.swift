import AppKit

/// Vigila los arrastres de archivos del sistema con monitores globales y el drag pasteboard (§3.1).
/// No necesita permiso de Accesibilidad (Paso 0, punto 1).
@MainActor
final class DragMonitor {
    private let controller: RingController
    private var monitor: Any?

    private var countAtMouseDown = 0
    private var pointAtMouseDown = NSPoint.zero
    /// Archivos del arrastre actual, leídos una vez por arrastre.
    private var sessionFiles: [DraggedFile]?

    init(controller: RingController) {
        self.controller = controller
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            // Los monitores globales llegan en el hilo principal
            MainActor.assumeIsolated { self?.handle(event) }
        }
        Log.arrastre.info("Monitor global instalado: \(self.monitor != nil)")
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let pasteboard = NSPasteboard(name: .drag)
        switch event.type {
        case .leftMouseDown:
            countAtMouseDown = pasteboard.changeCount
            pointAtMouseDown = NSEvent.mouseLocation
            sessionFiles = nil

        case .leftMouseDragged:
            // Solo arrastres reales: el drag pasteboard ha cambiado desde el mouseDown
            guard pasteboard.changeCount != countAtMouseDown else { return }
            let flags = NSEvent.modifierFlags
            let kind = RingKind.from(shift: flags.contains(.shift), option: flags.contains(.option),
                                     command: flags.contains(.command), control: flags.contains(.control))
            let location = NSEvent.mouseLocation

            if controller.isAttachedToDrag {
                // Visible: sigue a los modificadores; sin teclas se queda el último anillo
                if let kind { controller.switchKind(kind) }
                return
            }
            guard let kind, hypot(location.x - pointAtMouseDown.x, location.y - pointAtMouseDown.y) >= 8 else { return }
            let files = sessionFiles ?? readFiles(from: pasteboard)
            sessionFiles = files
            guard !files.isEmpty else { return }
            controller.show(kind: kind, files: files, at: location)

        case .leftMouseUp:
            sessionFiles = nil
            controller.mouseUp()

        default:
            break
        }
    }

    /// Lee y clasifica los archivos del drag pasteboard. Los vídeos se comprueban con ffprobe.
    private func readFiles(from pasteboard: NSPasteboard) -> [DraggedFile] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.map(DraggedFile.inspect)
    }
}
