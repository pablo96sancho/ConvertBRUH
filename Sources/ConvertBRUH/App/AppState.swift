import Foundation

/// Estado compartido con el menú de la barra.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var activeJobs = 0
    @Published var lastError: String?
    @Published var launchAtLogin = LoginItem.isEnabled

    func jobStarted() { activeJobs += 1 }
    func jobFinished() { activeJobs = max(0, activeJobs - 1) }

    func report(_ message: String) {
        lastError = message
        Log.app.error("\(message, privacy: .public)")
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
        } catch {
            report("No se pudo cambiar el inicio de sesión: \(error.localizedDescription)")
        }
        launchAtLogin = LoginItem.isEnabled
    }
}
