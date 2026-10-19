import Foundation

/// Los tres anillos, según los modificadores pulsados durante el arrastre.
enum RingKind: Equatable {
    case convertir      // Shift
    case acciones       // Option
    case herramientas   // Control

    /// Una sola tecla → anillo. Combinaciones (o Command) no eligen ninguno, así que al pasar
    /// de una tecla a otra el anillo visible se queda como está hasta que solo quede una.
    static func from(shift: Bool, option: Bool, command: Bool, control: Bool) -> RingKind? {
        guard !command else { return nil }
        switch (shift, option, control) {
        case (true, false, false): return .convertir
        case (false, true, false): return .acciones
        case (false, false, true): return .herramientas
        default: return nil
        }
    }
}

/// Acciones sobre archivos del anillo Option (§3.6).
enum FileAction: String, CaseIterable, Equatable {
    // Orden horario desde arriba
    case airdrop, float, copy, move, copyPath

    var label: String {
        switch self {
        case .airdrop: "AIRDROP"
        case .float: "FLOAT"
        case .copy: "COPY"
        case .move: "MOVE"
        case .copyPath: "COPY PATH"
        }
    }

    var symbol: String {
        switch self {
        case .airdrop: "dot.radiowaves.up.forward"
        case .float: "pin"
        case .copy: "doc.on.doc"
        case .move: "folder"
        case .copyPath: "doc.text"
        }
    }
}

/// Qué hace una porción al soltar sobre ella.
enum SliceOperation: Equatable {
    case convert(TargetFormat)
    case action(FileAction)
    case tool(ToolKind)
}

struct RingSlice: Identifiable, Equatable {
    let operation: SliceOperation
    var id: String { label }

    var label: String {
        switch operation {
        case .convert(let f): f.label
        case .action(let a): a.label
        case .tool(let t): t.label
        }
    }

    /// SF Symbol encima de la etiqueta (solo Acciones y Herramientas).
    var symbol: String? {
        switch operation {
        case .convert: nil
        case .action(let a): a.symbol
        case .tool(let t): t.symbol
        }
    }

    /// Porciones de un anillo para los archivos arrastrados. Vacío = no se muestra el anillo.
    static func slices(for kind: RingKind, files: [DraggedFile]) -> [RingSlice] {
        switch kind {
        case .convertir:
            return TargetFormat.available(for: files).map { RingSlice(operation: .convert($0)) }
        case .acciones:
            guard !files.isEmpty else { return [] }
            return FileAction.allCases.map { RingSlice(operation: .action($0)) }
        case .herramientas:
            return ToolKind.available(for: files).map { RingSlice(operation: .tool($0)) }
        }
    }
}
