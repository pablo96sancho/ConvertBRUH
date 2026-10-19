import AppKit
import QuickLookThumbnailing

/// FLOAT: miniatura flotante siempre encima que se puede volver a arrastrar a cualquier app.
@MainActor
final class FloatPanel: NSPanel {
    private let onClose: (FloatPanel) -> Void

    init(urls: [URL], onClose: @escaping (FloatPanel) -> Void) {
        self.onClose = onClose
        let size = NSSize(width: 132, height: 156)
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = FloatContentView(frame: NSRect(origin: .zero, size: size), urls: urls) { [weak self] in
            self?.closeFloat()
        }
    }

    override var canBecomeKey: Bool { false }

    func closeFloat() {
        orderOut(nil)
        onClose(self)
    }
}

/// Contenido: miniatura + nombre; arrastrar desde la miniatura inicia un drag de archivos,
/// arrastrar desde el borde mueve la ventana.
private final class FloatContentView: NSView, NSDraggingSource {
    private let urls: [URL]
    private let thumbnail = NSImageView()
    private let onClose: () -> Void
    private var mouseDownPoint: NSPoint?

    init(frame: NSRect, urls: [URL], onClose: @escaping () -> Void) {
        self.urls = urls
        self.onClose = onClose
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        layer?.cornerRadius = 18
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.borderWidth = 1

        thumbnail.frame = NSRect(x: 16, y: 38, width: 100, height: 100)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.image = NSWorkspace.shared.icon(forFile: urls[0].path)
        addSubview(thumbnail)

        let name = NSTextField(labelWithString: urls.count > 1 ? "\(urls.count) archivos" : urls[0].lastPathComponent)
        name.frame = NSRect(x: 8, y: 12, width: frame.width - 16, height: 18)
        name.alignment = .center
        name.textColor = .white
        name.font = .systemFont(ofSize: 11, weight: .bold)
        name.lineBreakMode = .byTruncatingMiddle
        addSubview(name)

        let close = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Cerrar")!,
                             target: self, action: #selector(closeTapped))
        close.isBordered = false
        close.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        close.frame = NSRect(x: frame.width - 26, y: frame.height - 26, width: 20, height: 20)
        addSubview(close)

        if urls.count > 1 {
            let badge = NSTextField(labelWithString: "\(urls.count)")
            badge.font = .systemFont(ofSize: 11, weight: .heavy)
            badge.textColor = .white
            badge.alignment = .center
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.systemBlue.cgColor
            badge.layer?.cornerRadius = 9
            badge.frame = NSRect(x: 8, y: frame.height - 26, width: 26, height: 18)
            addSubview(badge)
        }

        let request = QLThumbnailGenerator.Request(fileAt: urls[0], size: CGSize(width: 100, height: 100),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let rep else { return }
            DispatchQueue.main.async { self?.thumbnail.image = rep.nsImage }
        }
    }

    required init?(coder: NSCoder) { fatalError("no usado") }

    @objc private func closeTapped() { onClose() }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        mouseDownPoint = nil
        if thumbnail.frame.insetBy(dx: -6, dy: -6).contains(start) {
            let items = urls.enumerated().map { i, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let offset = CGFloat(min(i, 4)) * 4
                item.setDraggingFrame(thumbnail.frame.offsetBy(dx: offset, dy: -offset), contents: thumbnail.image)
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        } else {
            window?.performDrag(with: event)
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Solo copiar/enlazar: soltarlo en Finder nunca mueve el original
        context == .outsideApplication ? [.copy, .generic, .link] : []
    }
}
