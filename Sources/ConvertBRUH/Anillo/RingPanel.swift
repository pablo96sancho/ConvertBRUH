import AppKit
import SwiftUI

/// Panel flotante, no activante, que recibe el drop (§3.2).
final class RingPanel: NSPanel {
    static let margin: CGFloat = 16

    let dropView: RingDropView

    init(model: RingModel) {
        let size = model.geometry.diameter + RingPanel.margin * 2
        dropView = RingDropView(frame: NSRect(x: 0, y: 0, width: size, height: size), model: model)
        super.init(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        contentView = dropView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Centra el panel en `point`, recolocado dentro del `visibleFrame` de la pantalla del cursor.
    func center(at point: NSPoint) {
        let size = frame.size
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - size.height)
        }
        setFrameOrigin(origin)
    }
}

/// Respuesta háptica en trackpads Force Touch (con ratón no hace nada).
/// Durante el arrastre el dedo está sobre el trackpad, que es cuando macOS la reproduce.
enum Haptics {
    /// Cambio de porción.
    static func tick() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    /// Entrar en el centro (cancelar).
    static func soft() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
    /// Cambio de anillo con la tecla.
    static func level() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
}

/// Vista contenedora: aloja el SwiftUI y hace de destino del arrastre.
final class RingDropView: NSView {
    let model: RingModel
    /// Se llama al soltar sobre una porción.
    var onDrop: ((RingSlice, [URL]) -> Void)?

    init(frame: NSRect, model: RingModel) {
        self.model = model
        super.init(frame: frame)
        let host = NSHostingView(rootView: RingView(model: model))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("no usado") }

    private func hit(_ sender: NSDraggingInfo) -> RingGeometry.Hit {
        let p = convert(sender.draggingLocation, from: nil)
        // Coordenadas relativas al centro, con y hacia arriba (AppKit)
        return model.geometry.hit(CGPoint(x: p.x - bounds.midX, y: p.y - bounds.midY))
    }

    private func updateHover(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard model.phase == .choosing else {
            model.hovered = nil
            model.centerHovered = false
            return []
        }
        switch hit(sender) {
        case .slice(let i):
            if model.hovered != i {
                model.hovered = i
                Haptics.tick()
            }
            model.centerHovered = false
            return .copy
        case .center:
            model.hovered = nil
            if !model.centerHovered { Haptics.soft() }
            model.centerHovered = true
            return .copy
        case .outside:
            model.hovered = nil
            model.centerHovered = false
            return []
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateHover(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateHover(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.hovered = nil
        model.centerHovered = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            model.hovered = nil
            model.centerHovered = false
        }
        guard model.phase == .choosing, case .slice(let i) = hit(sender), model.slices.indices.contains(i) else {
            return false // centro o fuera: cancelar
        }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop?(model.slices[i], urls)
        return true
    }
}
