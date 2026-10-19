import Foundation

/// Rutas de los binarios incluidos en el bundle.
enum Binaries {
    static var ffmpeg: URL { bin("ffmpeg") }
    static var ffprobe: URL { bin("ffprobe") }

    private static func bin(_ name: String) -> URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin/\(name)")
        if let bundled, FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        // Desarrollo (`swift run`): Resources/bin del repo
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/bin/\(name)")
    }

    /// `aac_at` está disponible en nuestro build (Paso 0). Se comprueba una vez por si cambia el binario.
    static let hasAACAT: Bool = {
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-hide_banner", "-encoders"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).contains(" aac_at ")
    }()
}

/// Registro de procesos y temporales vivos, para limpiarlos al salir (§5.3).
/// Síncrono a propósito: `applicationWillTerminate` no puede esperar a un actor.
final class ProcessRegistry: @unchecked Sendable {
    static let shared = ProcessRegistry()
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]
    private var temporaries: Set<URL> = []

    func add(_ p: Process) { lock.withLock { processes[ObjectIdentifier(p)] = p } }
    func remove(_ p: Process) { lock.withLock { _ = processes.removeValue(forKey: ObjectIdentifier(p)) } }
    func addTemporary(_ url: URL) { lock.withLock { _ = temporaries.insert(url) } }
    func removeTemporary(_ url: URL) { lock.withLock { _ = temporaries.remove(url) } }

    /// Termina todo y borra los temporales.
    func terminateAll() {
        let (procs, temps) = lock.withLock { (Array(processes.values), temporaries) }
        for p in procs where p.isRunning { p.terminate() }
        for p in procs { p.waitUntilExit() }
        for t in temps { try? FileManager.default.removeItem(at: t) }
    }
}

/// Ejecuta ffmpeg/ffprobe con `Process` (nunca con shell).
enum FFmpegRunner {
    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Ejecuta y espera. `onProgressMicroseconds` recibe `out_time_us` de `-progress pipe:1`.
    /// Cancelar la tarea termina el proceso.
    static func run(executable: URL, arguments: [String],
                    onProgressMicroseconds: (@Sendable (Int64) -> Void)? = nil) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let collector = OutputCollector()
        outPipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            let lines = collector.appendOut(data)
            if let onProgressMicroseconds {
                for line in lines where line.hasPrefix("out_time_us=") {
                    if let v = Int64(line.dropFirst("out_time_us=".count)), v >= 0 { onProgressMicroseconds(v) }
                }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if !data.isEmpty { collector.appendErr(data) }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Result, Error>) in
                process.terminationHandler = { p in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    // Lo que quede en los pipes
                    _ = collector.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
                    collector.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
                    ProcessRegistry.shared.remove(p)
                    cont.resume(returning: Result(status: p.terminationStatus, stdout: collector.out, stderr: collector.err))
                }
                do {
                    try process.run()
                    ProcessRegistry.shared.add(process)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// stderr resumido para mostrar en el menú (máx. 200 caracteres).
    static func summarize(_ stderr: String) -> String {
        let lines = stderr.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let text = lines.suffix(2).joined(separator: " · ")
        if text.isEmpty { return "ffmpeg falló" }
        return text.count > 200 ? String(text.prefix(199)) + "…" : text
    }
}

/// Acumula stdout/stderr desde los handlers de los pipes.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()
    private var pendingLine = ""

    /// Añade datos y devuelve las líneas completas nuevas.
    func appendOut(_ data: Data) -> [String] {
        lock.withLock {
            outData.append(data)
            pendingLine += String(decoding: data, as: UTF8.self)
            var lines = pendingLine.components(separatedBy: "\n")
            pendingLine = lines.removeLast()
            return lines
        }
    }

    func appendErr(_ data: Data) { lock.withLock { errData.append(data) } }
    var out: String { lock.withLock { String(decoding: outData, as: UTF8.self) } }
    var err: String { lock.withLock { String(decoding: errData, as: UTF8.self) } }
}
