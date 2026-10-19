import AppKit

/// Coordina el panel del anillo con el arrastre, los trabajos y las acciones.
@MainActor
final class RingController {
    private let model = RingModel()
    private lazy var panel: RingPanel = {
        let p = RingPanel(model: model)
        p.dropView.onDrop = { [weak self] slice, urls in self?.dropped(slice, urls: urls) }
        return p
    }()
    private let state: AppState
    private let actions = FileActions()

    /// Archivos del arrastre al que está ligado el anillo.
    private var files: [DraggedFile] = []
    /// `true` desde que aparece el anillo hasta el `leftMouseUp` de ese arrastre.
    private(set) var isAttachedToDrag = false
    /// Lote que el anillo está mostrando (los lotes siguen aunque el anillo pase a otro arrastre).
    private var shownBatch: UUID?
    private var hideWork: DispatchWorkItem?

    init(state: AppState) {
        self.state = state
    }

    // MARK: - Arrastre

    func show(kind: RingKind, files: [DraggedFile], at point: NSPoint) {
        let slices = RingSlice.slices(for: kind, files: files)
        guard !slices.isEmpty else { return }
        cancelPendingHide()
        self.files = files
        shownBatch = nil
        isAttachedToDrag = true
        model.kind = kind
        model.slices = slices
        model.hovered = nil
        model.centerHovered = false
        model.phase = .choosing
        model.sizeText = Self.sizeText(for: files, kind: kind)
        panel.alphaValue = 1
        panel.center(at: point)
        panel.orderFrontRegardless()
        Log.arrastre.info("Anillo \(String(describing: kind), privacy: .public) con \(slices.count) porciones")
    }

    /// Cambio de modificadores con el anillo visible.
    func switchKind(_ kind: RingKind) {
        guard isAttachedToDrag, model.phase == .choosing, kind != model.kind else { return }
        let slices = RingSlice.slices(for: kind, files: files)
        guard !slices.isEmpty else {
            // El nuevo anillo no tendría porciones: se cierra
            hide(animated: true)
            isAttachedToDrag = false
            return
        }
        model.kind = kind
        model.slices = slices
        model.hovered = nil
        model.sizeText = Self.sizeText(for: files, kind: kind)
    }

    func mouseUp() {
        guard isAttachedToDrag else { return }
        isAttachedToDrag = false
        // El leftMouseUp global llega antes que performDragOperation (Paso 0): se espera un poco
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.phase == .choosing else { return }
            self.hide(animated: true)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // MARK: - Drop

    private func dropped(_ slice: RingSlice, urls: [URL]) {
        cancelPendingHide()
        Log.arrastre.info("Drop en \(slice.label, privacy: .public)")
        switch slice.operation {
        case .action(let action):
            runAction(action)
        case .convert, .tool:
            startBatch(slice.operation)
        }
    }

    private func runAction(_ action: FileAction) {
        let urls = files.map(\.url)
        switch action {
        case .copy, .copyPath:
            action == .copy ? actions.copy(urls) : actions.copyPath(urls)
            model.phase = .success
            hide(after: 0.5)
        case .airdrop:
            hide(animated: false)
            actions.airDrop(urls)
        case .move:
            hide(animated: false)
            actions.move(urls) { [weak self] error in
                if let error { self?.state.report(error) }
            }
        case .float:
            hide(animated: false)
            actions.float(urls)
        }
    }

    // MARK: - Lotes de Convertir / Herramientas

    private func startBatch(_ operation: SliceOperation) {
        let targets = files.filter { file in
            switch operation {
            case .convert(let f): f.isAudio ? file.hasUsableAudio : file.kind == .image
            case .tool(let t): t.isValid(for: file)
            case .action: false
            }
        }
        guard !targets.isEmpty else { hide(animated: true); return }

        let batch = Batch(count: targets.count)
        shownBatch = batch.id
        updateCenter(batch)

        for (i, file) in targets.enumerated() {
            state.jobStarted()
            Task { @MainActor [weak self] in
                do {
                    let output = try await ConversionQueue.shared.run {
                        try await JobRunner.run(file, operation) { p in
                            Task { @MainActor in
                                guard p > batch.progress[i] else { return }
                                batch.progress[i] = p
                                self?.updateCenter(batch)
                            }
                        }
                    }
                    batch.created.append(output.url)
                    batch.usedFallback = batch.usedFallback || output.usedFallback
                } catch {
                    batch.errors.append("\(file.url.lastPathComponent): \(error.localizedDescription)")
                }
                batch.finished += 1
                self?.state.jobFinished()
                self?.updateCenter(batch)
                if batch.finished == batch.count { self?.batchFinished(batch) }
            }
        }
    }

    /// Progreso agregado de un drop.
    @MainActor
    private final class Batch {
        let id = UUID()
        let count: Int
        var progress: [Double]
        var finished = 0
        var created: [URL] = []
        var errors: [String] = []
        var usedFallback = false

        init(count: Int) {
            self.count = count
            progress = Array(repeating: 0, count: count)
        }
    }

    private func updateCenter(_ batch: Batch) {
        guard shownBatch == batch.id, batch.finished < batch.count else { return }
        if batch.count == 1 {
            model.phase = .working("\(Int((batch.progress[0] * 100).rounded(.down))) %")
        } else {
            model.phase = .working("\(batch.finished)/\(batch.count)")
        }
    }

    private func batchFinished(_ batch: Batch) {
        if !batch.created.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(batch.created)
        }
        if !batch.errors.isEmpty {
            let summary = batch.errors.count == 1
                ? batch.errors[0]
                : "\(batch.errors.count) fallos: " + batch.errors.joined(separator: " · ")
            state.report(summary)
        } else if batch.usedFallback {
            state.report("La carpeta original no admite escritura: guardado en Descargas")
        }

        guard shownBatch == batch.id else { return }
        shownBatch = nil
        if batch.errors.isEmpty {
            model.phase = .working(batch.count == 1 ? "100 %" : "\(batch.count)/\(batch.count)")
            hide(animated: true)
        } else {
            model.phase = .error
            hide(after: 2)
        }
    }

    // MARK: - Ocultar

    private func hide(after delay: TimeInterval) {
        cancelPendingHide()
        let work = DispatchWorkItem { [weak self] in self?.hide(animated: true) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    private func hide(animated: Bool) {
        cancelPendingHide()
        guard panel.isVisible else { return }
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.panel.alphaValue == 0 else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        })
    }

    // MARK: - Centro

    static func sizeText(for files: [DraggedFile], kind: RingKind) -> String {
        let relevant: [DraggedFile]
        switch kind {
        case .acciones: relevant = files
        case .convertir, .herramientas: relevant = files.filter { $0.hasUsableAudio || $0.kind == .image }
        }
        var bytes: Int64 = 0
        var folders = 0
        for f in relevant {
            let v = try? f.url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if v?.isDirectory == true { folders += 1 } else { bytes += Int64(v?.fileSize ?? 0) }
        }
        if bytes == 0 && folders > 0 {
            return relevant.count == 1 ? "Carpeta" : "\(relevant.count) ítems"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
