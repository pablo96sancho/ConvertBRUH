// Paso 0 — Prototipo .app (puntos 1–4, 7, 8 y 9 del CLAUDE.md).
// Se monta con build.sh porque el login item y ffmpeg-dentro-del-bundle necesitan un .app real.
// Log en ~/Library/Logs/Paso0.log
//
// Arrastre con Shift        → anillo "convertir" (solo registra el drop)
// Arrastre con Option       → anillo "acciones": el drop abre AirDrop y crea una ventana Float
// Arrastre con Shift+Option → anillo "herramientas" (solo registra el drop)
// Menú P0 → "Pruebas automáticas": ffmpeg del bundle, escritura TCC y login item

import AppKit
import ServiceManagement
import QuickLookThumbnailing

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Paso0.log")
let horaFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

func log(_ tag: String, _ msg: String) {
    let linea = "\(horaFormatter.string(from: Date())) [\(tag)] \(msg)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(Data(linea.utf8)); try? h.close()
    } else {
        try? linea.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

enum Modo: String { case convertir, acciones, herramientas }

func modoActual() -> Modo? {
    let f = NSEvent.modifierFlags.intersection([.shift, .option, .command, .control])
    switch f {
    case [.shift]: return .convertir
    case [.option]: return .acciones
    case [.shift, .option]: return .herramientas
    default: return nil
    }
}

// MARK: - Destino del drop

final class VistaDestino: NSView {
    var modo: Modo = .convertir { didSet { pintar() } }
    var alSoltar: (([URL], Modo) -> Void)?
    private var actualizaciones = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.cornerRadius = frame.width / 2
        pintar()
    }
    required init?(coder: NSCoder) { fatalError("no usado") }

    private func pintar() {
        let color: NSColor = switch modo { case .convertir: .systemOrange; case .acciones: .systemBlue; case .herramientas: .systemPurple }
        layer?.backgroundColor = color.withAlphaComponent(0.6).cgColor
    }

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { log("P3", "draggingEntered"); return .copy }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        actualizaciones += 1
        if actualizaciones % 40 == 1 { log("P3", "draggingUpdated #\(actualizaciones)") }
        return .copy
    }
    override func draggingExited(_ s: NSDraggingInfo?) { log("P3", "draggingExited") }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        log("P3", "performDragOperation ✅ modo=\(modo.rawValue) urls=\(urls.map(\.path))")
        alSoltar?(urls, modo)
        return true
    }
}

// MARK: - Float (punto 9): ventana flotante que es origen de arrastre

final class VistaFloat: NSView, NSDraggingSource {
    let urls: [URL]
    let imagen = NSImageView()

    init(urls: [URL]) {
        self.urls = urls
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 140))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        layer?.cornerRadius = 14
        imagen.frame = NSRect(x: 10, y: 30, width: 100, height: 100)
        imagen.image = NSWorkspace.shared.icon(forFile: urls[0].path)
        addSubview(imagen)
        let nombre = NSTextField(labelWithString: urls.count > 1 ? "\(urls.count) archivos" : urls[0].lastPathComponent)
        nombre.frame = NSRect(x: 6, y: 6, width: 108, height: 18)
        nombre.textColor = .white; nombre.font = .boldSystemFont(ofSize: 11); nombre.lineBreakMode = .byTruncatingMiddle
        addSubview(nombre)
        let req = QLThumbnailGenerator.Request(fileAt: urls[0], size: CGSize(width: 100, height: 100), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            if let rep { DispatchQueue.main.async { self.imagen.image = rep.nsImage } }
        }
    }
    required init?(coder: NSCoder) { fatalError("no usado") }

    override func mouseDown(with e: NSEvent) {} // evita que el panel lo trate como arrastre de ventana
    override func mouseDragged(with e: NSEvent) {
        let items = urls.map { url -> NSDraggingItem in
            let it = NSDraggingItem(pasteboardWriter: url as NSURL)
            it.setDraggingFrame(imagen.frame, contents: imagen.image)
            return it
        }
        beginDraggingSession(with: items, event: e, source: self)
        log("P9", "Float: sesión de arrastre iniciada con \(urls.count) archivo(s)")
    }
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { [.copy, .generic, .move] }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) {
        log("P9", "Float: arrastre terminado, operación=\(operation.rawValue) (0 = cancelado)")
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var panel: NSPanel!
    var vista: VistaDestino!
    var floats: [NSPanel] = []
    var countAlBajar = 0, puntoAlBajar = NSPoint.zero
    var ultimoModo: Modo?

    func applicationDidFinishLaunching(_ n: Notification) {
        log("INFO", "=== arranque · AXIsProcessTrusted=\(AXIsProcessTrusted()) · \(Bundle.main.bundlePath)")
        log("P5", "ImageIO escribe WebP: \(((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []).contains("org.webmproject.webp"))")

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "P0"
        let m = NSMenu()
        for (t, s) in [("Pruebas automáticas (ffmpeg, TCC, login)", #selector(pruebasAuto)),
                       ("Login item: register", #selector(loginReg)),
                       ("Login item: unregister", #selector(loginUnreg)),
                       ("Salir", #selector(salir))] {
            let mi = NSMenuItem(title: t, action: s, keyEquivalent: ""); mi.target = self; m.addItem(mi)
        }
        item.menu = m

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.hidesOnDeactivate = false
        vista = VistaDestino(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        vista.alSoltar = { [weak self] urls, modo in self?.soltado(urls, modo) }
        panel.contentView = vista

        _ = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] e in self?.manejar(e) }
        log("P1", "Monitor global instalado")
    }

    func manejar(_ e: NSEvent) {
        let pb = NSPasteboard(name: .drag)
        switch e.type {
        case .leftMouseDown:
            countAlBajar = pb.changeCount; puntoAlBajar = NSEvent.mouseLocation; ultimoModo = nil
        case .leftMouseDragged:
            guard pb.changeCount != countAlBajar else { return }
            let modo = modoActual()
            if modo != ultimoModo {
                log("P1", "Modificadores durante arrastre → \(modo?.rawValue ?? "ninguno") (flags=\(NSEvent.modifierFlags.rawValue))")
                ultimoModo = modo
            }
            if panel.isVisible {
                if let modo, modo != vista.modo { vista.modo = modo; log("P1", "Anillo cambia en vivo a \(modo.rawValue)") }
                return
            }
            let p = NSEvent.mouseLocation
            guard let modo, hypot(p.x - puntoAlBajar.x, p.y - puntoAlBajar.y) >= 8 else { return }
            let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            let tipos = pb.types?.map(\.rawValue) ?? []
            log("P2", "changeCount \(countAlBajar)→\(pb.changeCount) urls=\(urls.map(\.lastPathComponent)) tipos=\(tipos.prefix(6))")
            guard !urls.isEmpty else { return }
            vista.modo = modo
            panel.setFrameOrigin(NSPoint(x: p.x - 150, y: p.y - 150))
            panel.orderFrontRegardless()
            log("P3", "Panel mostrado (\(modo.rawValue)) · app activa: \(NSApp.isActive)")
        case .leftMouseUp:
            if panel.isVisible { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.panel.orderOut(nil) } }
        default: break
        }
    }

    func soltado(_ urls: [URL], _ modo: Modo) {
        guard modo == .acciones, !urls.isEmpty else { return }
        // Punto 9a: AirDrop desde app agente sin activarla
        if let s = NSSharingService(named: .sendViaAirDrop) {
            log("P9", "AirDrop canPerform=\(s.canPerform(withItems: urls))")
            s.perform(withItems: urls)
            log("P9", "AirDrop perform llamado · app activa: \(NSApp.isActive)")
        } else { log("P9", "AirDrop: servicio no disponible") }
        // Punto 9b: ventana Float arrastrable
        let f = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 140), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        f.level = .floating; f.isOpaque = false; f.backgroundColor = .clear; f.hasShadow = true; f.hidesOnDeactivate = false
        f.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        f.contentView = VistaFloat(urls: urls)
        let p = NSEvent.mouseLocation
        f.setFrameOrigin(NSPoint(x: p.x + 160, y: p.y - 70))
        f.orderFrontRegardless()
        floats.append(f)
        log("P9", "Float mostrado; arrástralo a Finder o Ableton")
    }

    // MARK: Pruebas automáticas

    @objc func pruebasAuto() {
        // Punto 4: ffmpeg/ffprobe desde dentro del bundle firmado
        for b in ["ffmpeg", "ffprobe"] {
            let p = Process()
            p.executableURL = Bundle.main.resourceURL!.appendingPathComponent("bin/\(b)")
            p.arguments = ["-hide_banner", "-version"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            do {
                try p.run(); p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                log("P4", "\(b) status=\(p.terminationStatus) \(out.split(separator: "\n").first ?? "")")
            } catch { log("P4", "\(b) ERROR \(error)") }
        }
        // Punto 7: escritura en carpetas protegidas
        let home = FileManager.default.homeDirectoryForCurrentUser
        var dirs = ["Desktop", "Documents", "Downloads", "Library/Mobile Documents/com~apple~CloudDocs"].map { home.appendingPathComponent($0) }
        dirs += ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)) ?? [])
        for d in dirs {
            let f = d.appendingPathComponent("convertbruh-paso0-\(UUID().uuidString.prefix(6)).txt")
            do {
                try "x".write(to: f, atomically: false, encoding: .utf8)
                try FileManager.default.removeItem(at: f)
                log("P7", "OK escritura en \(d.path)")
            } catch { log("P7", "FALLO en \(d.path): \((error as NSError).code) \(error.localizedDescription)") }
        }
        loginReg()
        log("P8", "status tras register=\(SMAppService.mainApp.status.rawValue) (1=enabled, 2=requiresApproval)")
    }

    @objc func loginReg() {
        do { try SMAppService.mainApp.register(); log("P8", "register OK status=\(SMAppService.mainApp.status.rawValue)") }
        catch { log("P8", "register ERROR \(error)") }
    }
    @objc func loginUnreg() {
        do { try SMAppService.mainApp.unregister(); log("P8", "unregister OK status=\(SMAppService.mainApp.status.rawValue)") }
        catch { log("P8", "unregister ERROR \(error)") }
    }
    @objc func salir() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegado = App()
app.delegate = delegado
app.setActivationPolicy(.accessory)
app.run()
