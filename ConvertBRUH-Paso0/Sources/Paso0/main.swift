// Paso 0 — Prototipo de verificación para ConvertBRUH.
// Comprueba los puntos 1, 2, 3 y 5 del CLAUDE.md:
//   1. ¿El monitor global recibe eventos de ratón durante un arrastre de Finder sin Accesibilidad?
//   2. ¿El drag pasteboard cambia y expone las file URLs durante el arrastre?
//   3. ¿Un NSPanel no-activante mostrado a mitad de arrastre recibe el drop?
//   5. ¿ImageIO puede escribir WebP?
// Uso: swift run   (y luego Shift + arrastrar archivos desde Finder / Escritorio / Ableton)

import AppKit
import ImageIO

// MARK: - Log

let horaFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

func log(_ tag: String, _ msg: String) {
    print("\(horaFormatter.string(from: Date())) [\(tag)] \(msg)")
    fflush(stdout)
}

// MARK: - Punto 5: WebP en ImageIO

func comprobarWebP() {
    let tipos = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
    let soporta = tipos.contains("org.webmproject.webp")
    log("P5", "ImageIO puede escribir WebP: \(soporta ? "SÍ" : "NO")")
}

// MARK: - Lectura del drag pasteboard

func urlsDelArrastre() -> [URL] {
    let pb = NSPasteboard(name: .drag)
    let objs = pb.readObjects(forClasses: [NSURL.self],
                              options: [.urlReadingFileURLsOnly: true]) as? [URL]
    return objs ?? []
}

// MARK: - Punto 3: vista destino del drop

final class VistaDestino: NSView {
    private var actualizaciones = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        layer?.cornerRadius = frame.width / 2
    }

    required init?(coder: NSCoder) { fatalError("no usado") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        actualizaciones = 0
        log("P3", "draggingEntered ✅")
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.7).cgColor
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        actualizaciones += 1
        // Solo se loguea cada 20 eventos para no inundar la consola
        if actualizaciones % 20 == 1 {
            let p = convert(sender.draggingLocation, from: nil)
            log("P3", "draggingUpdated #\(actualizaciones) en (\(Int(p.x)), \(Int(p.y)))")
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        log("P3", "draggingExited")
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        log("P3", "performDragOperation ✅ — \(urls.count) archivo(s): \(urls.map(\.lastPathComponent))")
        return true
    }
}

// MARK: - Panel del anillo (prototipo: círculo simple)

final class PanelAnillo {
    private let tamano: CGFloat = 300
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: tamano, height: tamano),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = VistaDestino(frame: NSRect(x: 0, y: 0, width: tamano, height: tamano))
        return p
    }()

    var visible: Bool { panel.isVisible }

    func mostrar(en punto: NSPoint) {
        // Centrar en el cursor y recolocar dentro de la pantalla actual
        let pantalla = NSScreen.screens.first { NSMouseInRect(punto, $0.frame, false) } ?? NSScreen.main
        var origen = NSPoint(x: punto.x - tamano / 2, y: punto.y - tamano / 2)
        if let vf = pantalla?.visibleFrame {
            origen.x = min(max(origen.x, vf.minX), vf.maxX - tamano)
            origen.y = min(max(origen.y, vf.minY), vf.maxY - tamano)
        }
        panel.setFrameOrigin(origen)
        panel.orderFrontRegardless()
        log("P3", "Panel mostrado en (\(Int(origen.x)), \(Int(origen.y))) — app activa: \(NSApp.isActive)")
    }

    func ocultar() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        log("P3", "Panel oculto")
    }
}

// MARK: - Puntos 1 y 2: monitor global + polling de respaldo

final class MonitorArrastre {
    private let anillo = PanelAnillo()
    private var countAlBajar = 0
    private var puntoAlBajar = NSPoint.zero
    private var draggedRecibidos = 0
    private var arrastreDetectado = false
    private var ultimoShift = false

    // Polling de respaldo por si el monitor global no recibe eventos durante el drag
    private var ultimoCountPoll = NSPasteboard(name: .drag).changeCount
    private var botonPulsadoPoll = false

    func arrancar() {
        let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] evento in
            self?.manejar(evento)
        }
        log("P1", "Monitor global instalado: \(monitor != nil ? "SÍ" : "NO")")

        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.poll()
        }
        log("INFO", "Listo. Mantén Shift y arrastra archivos desde Finder, Escritorio o Ableton. Ctrl+C para salir.")
    }

    private func manejar(_ e: NSEvent) {
        switch e.type {
        case .leftMouseDown:
            countAlBajar = NSPasteboard(name: .drag).changeCount
            puntoAlBajar = NSEvent.mouseLocation
            draggedRecibidos = 0
            arrastreDetectado = false
            log("P1", "leftMouseDown — drag changeCount=\(countAlBajar)")

        case .leftMouseDragged:
            draggedRecibidos += 1
            let pb = NSPasteboard(name: .drag)
            let cambiado = pb.changeCount != countAlBajar
            let shift = NSEvent.modifierFlags.contains(.shift)
            let p = NSEvent.mouseLocation
            let distancia = hypot(p.x - puntoAlBajar.x, p.y - puntoAlBajar.y)

            if draggedRecibidos == 1 {
                log("P1", "Primer leftMouseDragged recibido ✅")
            }
            if shift != ultimoShift {
                log("P1", "Shift durante arrastre: \(shift)")
                ultimoShift = shift
            }
            if cambiado && !arrastreDetectado {
                arrastreDetectado = true
                let urls = urlsDelArrastre()
                log("P2", "changeCount cambió (\(countAlBajar) → \(pb.changeCount)) — URLs: \(urls.map(\.lastPathComponent))")
            }
            if cambiado && shift && distancia >= 8 && !anillo.visible && !urlsDelArrastre().isEmpty {
                anillo.mostrar(en: p)
            }

        case .leftMouseUp:
            log("P1", "leftMouseUp — leftMouseDragged recibidos: \(draggedRecibidos)")
            // Pequeño retraso para no cortar el performDragOperation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.anillo.ocultar()
            }

        default:
            break
        }
    }

    // Respaldo: detecta el arrastre sin depender de leftMouseDragged
    private func poll() {
        let pulsado = NSEvent.pressedMouseButtons & 1 == 1
        let count = NSPasteboard(name: .drag).changeCount
        if pulsado && count != ultimoCountPoll {
            log("POLL", "Arrastre detectado por polling — shift=\(NSEvent.modifierFlags.contains(.shift)) URLs: \(urlsDelArrastre().map(\.lastPathComponent))")
        }
        if pulsado != botonPulsadoPoll {
            botonPulsadoPoll = pulsado
        }
        ultimoCountPoll = count
    }
}

// MARK: - Arranque

final class Delegado: NSObject, NSApplicationDelegate {
    let monitor = MonitorArrastre()

    func applicationDidFinishLaunching(_ notification: Notification) {
        comprobarWebP()
        monitor.arrancar()
    }
}

let app = NSApplication.shared
let delegado = Delegado()
app.delegate = delegado
app.setActivationPolicy(.accessory)   // Sin Dock, como la app final
app.run()
