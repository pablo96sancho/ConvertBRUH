import CoreGraphics
import Foundation

/// Geometría del anillo: tamaños y punto → porción.
/// Ángulos en radianes medidos desde arriba en sentido horario; la porción 0 está centrada arriba.
struct RingGeometry: Equatable {
    var count: Int
    var outerRadius: CGFloat = 150
    var innerRadius: CGFloat = 62
    /// Borde negro del disco exterior.
    var rim: CGFloat = 8
    /// Separación entre porciones.
    var gap: CGFloat = 6

    var diameter: CGFloat { outerRadius * 2 }
    var sliceAngle: CGFloat { count > 0 ? 2 * .pi / CGFloat(count) : 0 }

    /// Ángulo central de una porción.
    func centerAngle(of index: Int) -> CGFloat { CGFloat(index) * sliceAngle }

    /// Resultado de localizar un punto relativo al centro (x a la derecha, y hacia arriba).
    enum Hit: Equatable {
        case center
        case slice(Int)
        case outside
    }

    func hit(_ p: CGPoint) -> Hit {
        let r = hypot(p.x, p.y)
        if r < innerRadius { return .center }
        guard r <= outerRadius, count > 0 else { return .outside }
        // atan2(x, y): 0 arriba, positivo hacia la derecha (horario)
        var a = atan2(p.x, p.y)
        if a < 0 { a += 2 * .pi }
        let index = Int(((a + sliceAngle / 2) / sliceAngle).rounded(.down)) % count
        return .slice(index)
    }

    /// Punto (coordenadas con y hacia abajo, origen en el centro) a un radio y ángulo dados.
    static func point(radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(x: radius * sin(angle), y: -radius * cos(angle))
    }
}
