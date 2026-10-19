import os

/// Loggers de la app. Ver en Consola filtrando por el subsystem.
enum Log {
    static let subsystem = "com.djokobeatz.convertbruh"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let arrastre = Logger(subsystem: subsystem, category: "arrastre")
    static let conversion = Logger(subsystem: subsystem, category: "conversion")
    static let acciones = Logger(subsystem: subsystem, category: "acciones")
}
