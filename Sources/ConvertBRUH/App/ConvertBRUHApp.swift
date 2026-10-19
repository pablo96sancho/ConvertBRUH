import AppKit
import SwiftUI

@main
struct ConvertBRUHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            // Con trabajos activos, el número junto al icono
            if state.activeJobs > 0 {
                Image(nsImage: MenuBarIcon.image)
                Text("\(state.activeJobs)")
            } else {
                Image(nsImage: MenuBarIcon.image)
            }
        }
    }
}

/// Icono plantilla de la barra (Resources/MenuBar, generado desde ICON APP/ con scripts/make-menubar-icon.swift).
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "ConvertBRUH")!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

private struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.activeJobs > 0 {
            Text("Conversiones en curso: \(state.activeJobs)")
        }
        if let error = state.lastError {
            Button("Último error: \(error.count > 60 ? String(error.prefix(59)) + "…" : error)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(error, forType: .string)
            }
        }
        if state.activeJobs > 0 || state.lastError != nil {
            Divider()
        }
        Toggle("Abrir al iniciar sesión", isOn: Binding(
            get: { state.launchAtLogin },
            set: { state.setLaunchAtLogin($0) }))
        Button("Cómo se usa") { showHelp() }
        Divider()
        Button("Salir de ConvertBRUH") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Cómo se usa ConvertBRUH"
        alert.informativeText = """
        Arrastra un archivo y, mientras lo arrastras, mantén:

        • Shift — Convertir (audio: MP3, WAV, M4A, FLAC, AIFF · imagen: JPG, PNG, WEBP, PDF · vídeo: MP4, MOV, GIF, AUDIO)
        • Option — Acciones (AirDrop, Float, Copy, Move, Copy Path)
        • Control — Herramientas (Normalize, Compress, Channels, Mute, Metadata)

        Suelta sobre una porción. Soltar en el centro cancela.
        """
        alert.runModal()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: DragMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = RingController(state: AppState.shared)
        let monitor = DragMonitor(controller: controller)
        monitor.start()
        self.monitor = monitor
        Log.app.info("ConvertBRUH arrancada · ffmpeg en \(Binaries.ffmpeg.path, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        // Matar ffmpeg y borrar temporales: nunca quedan archivos a medias
        ProcessRegistry.shared.terminateAll()
    }
}
