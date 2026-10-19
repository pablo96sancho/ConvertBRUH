import SwiftUI

/// Estado que pinta el anillo.
@MainActor
final class RingModel: ObservableObject {
    enum Phase: Equatable {
        case choosing
        case working(String)   // texto del centro: "37 %" o "2/5"
        case success
        case error
    }

    @Published var kind: RingKind = .convertir
    @Published var slices: [RingSlice] = []
    @Published var hovered: Int?
    @Published var centerHovered = false
    @Published var sizeText = ""
    @Published var phase: Phase = .choosing

    var geometry: RingGeometry { RingGeometry(count: slices.count) }

    /// Texto y color de la cápsula central según la fase.
    var centerText: (String, Color) {
        switch phase {
        case .choosing: return centerHovered ? ("Cancelar", .white) : (sizeText, .white)
        case .working(let t): return (t, .white)
        case .success: return ("✓", .white)
        case .error: return ("Error", Color(red: 1, green: 0.32, blue: 0.3))
        }
    }
}

/// Aspecto Liquid Glass (macOS 26+). Dos capas:
/// 1. Cristal: una pieza por porción, **siempre fija**. Si el cristal cambia, crece o es `.interactive()`,
///    el contenedor fusiona/deforma las piezas y aparece un "quesito" fantasma descuadrado.
/// 2. Encima, sin cristal: brillo + texto de cada porción. Esta capa es la que hace zoom en la activa.
@available(macOS 26.0, *)
struct GlassRingView: View {
    @ObservedObject var model: RingModel

    var body: some View {
        let g = model.geometry
        ZStack {
            // Disco: oscuro y translúcido para que el cristal de las porciones tenga contraste
            Circle()
                .fill(Color.black.opacity(0.3))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .padding(2)

            // spacing 0: las porciones nunca se fusionan entre sí
            GlassEffectContainer(spacing: 0) {
                ZStack {
                    ForEach(0..<model.slices.count, id: \.self) { i in
                        Color.clear
                            .frame(width: g.diameter, height: g.diameter)
                            .glassEffect(.regular.tint(.white.opacity(0.07)), in: RoundedSliceShape(geometry: g, index: i))
                    }
                }
            }
            .opacity(model.phase == .choosing ? 1 : 0.55)

            ForEach(Array(model.slices.enumerated()), id: \.element.id) { i, slice in
                sliceFace(slice, index: i, geometry: g)
            }

            glassCenter(g)
        }
        .frame(width: g.diameter, height: g.diameter)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: model.hovered)
        .animation(.easeOut(duration: 0.18), value: model.slices)
        .animation(.easeOut(duration: 0.18), value: model.phase)
    }

    /// Brillo + etiqueta de una porción; la activa se ilumina y hace zoom.
    private func sliceFace(_ slice: RingSlice, index i: Int, geometry g: RingGeometry) -> some View {
        let isHovered = model.hovered == i && model.phase == .choosing
        let dimmed = model.phase != .choosing
        let labelRadius = (g.innerRadius + g.outerRadius - g.rim) / 2 + 2
        let labelPoint = RingGeometry.point(radius: labelRadius, angle: g.centerAngle(of: i))
        // El zoom se ancla en el centro de la porción para que crezca "en su sitio"
        let anchor = UnitPoint(x: 0.5 + labelPoint.x / g.diameter, y: 0.5 + labelPoint.y / g.diameter)
        let shape = RoundedSliceShape(geometry: g, index: i)

        return VStack(spacing: 4) {
            if let symbol = slice.symbol {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
            }
            Text(slice.label)
                .font(.system(size: slice.symbol == nil ? 17 : 12, weight: .heavy))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize()
        }
        .foregroundStyle(Color.white.opacity(dimmed ? 0.35 : 1))
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        .offset(x: labelPoint.x, y: labelPoint.y)
        .frame(width: g.diameter, height: g.diameter)
        // Brillo de la porción activa con borde de luz, debajo del texto
        .background {
            shape.fill(Color.white.opacity(isHovered ? 0.28 : 0))
                .overlay(shape.stroke(Color.white.opacity(isHovered ? 0.45 : 0), lineWidth: 1))
                .shadow(color: .black.opacity(isHovered ? 0.35 : 0), radius: 8, y: 3)
        }
        .scaleEffect(isHovered ? 1.07 : 1, anchor: anchor)
        .zIndex(isHovered ? 1 : 0)
        .allowsHitTesting(false)
    }

    private func glassCenter(_ g: RingGeometry) -> some View {
        let (text, color) = model.centerText
        let cancel = model.centerHovered && model.phase == .choosing
        return Text(text)
            .font(.system(size: 15, weight: .heavy).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(cancel ? .regular.tint(.white.opacity(0.25)) : .regular, in: Capsule())
            .frame(maxWidth: g.innerRadius * 2 + 20)
    }
}

/// Sector anular con esquinas redondeadas.
/// Se dibuja encogido `cornerRadius` y luego se rellena + traza con ese grosor y uniones redondas.
struct SliceShape: Shape {
    var geometry: RingGeometry
    var index: Int
    var cornerRadius: CGFloat = 14
    var innerInset: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let mid = geometry.centerAngle(of: index)
        let half = geometry.sliceAngle / 2
        let rIn = geometry.innerRadius + innerInset + cornerRadius
        let rOut = geometry.outerRadius - geometry.rim - cornerRadius
        let d = geometry.gap / 2 + cornerRadius
        // Desplazamiento angular para que los lados queden paralelos al radio, a distancia `d`
        func delta(_ r: CGFloat) -> CGFloat { asin(min(d / r, 1)) }

        func pt(_ r: CGFloat, _ a: CGFloat) -> CGPoint {
            let p = RingGeometry.point(radius: r, angle: a)
            return CGPoint(x: c.x + p.x, y: c.y + p.y)
        }

        var path = Path()
        let steps = 32
        let outerFrom = mid - half + delta(rOut), outerTo = mid + half - delta(rOut)
        let innerFrom = mid + half - delta(rIn), innerTo = mid - half + delta(rIn)
        path.move(to: pt(rOut, outerFrom))
        for i in 1...steps { path.addLine(to: pt(rOut, outerFrom + (outerTo - outerFrom) * CGFloat(i) / CGFloat(steps))) }
        for i in 0...steps { path.addLine(to: pt(rIn, innerFrom + (innerTo - innerFrom) * CGFloat(i) / CGFloat(steps))) }
        path.closeSubpath()
        return path
    }
}

/// Porción con las esquinas redondeadas ya dentro del contorno (para `glassEffect(in:)`, que
/// necesita una forma real y no admite el truco de relleno + trazo).
@available(macOS 26.0, *)
struct RoundedSliceShape: Shape {
    var geometry: RingGeometry
    var index: Int
    var cornerRadius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let core = SliceShape(geometry: geometry, index: index, cornerRadius: cornerRadius).path(in: rect).cgPath
        // Contorno engordado con uniones redondas ∪ interior = sector con esquinas redondeadas
        let band = core.copy(strokingWithWidth: cornerRadius * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return Path(band.union(core))
    }
}

struct RingView: View {
    @ObservedObject var model: RingModel

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassRingView(model: model)
        } else {
            classicBody
        }
    }

    /// Aspecto para macOS 13–15: disco oscuro y porciones translúcidas.
    private var classicBody: some View {
        let g = model.geometry
        return ZStack {
            // Disco exterior oscuro
            Circle()
                .fill(Color.black.opacity(0.82))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))

            ForEach(Array(model.slices.enumerated()), id: \.element.id) { i, slice in
                sliceView(slice, index: i, geometry: g)
            }

            center(g)
        }
        .frame(width: g.diameter, height: g.diameter)
        .animation(.easeOut(duration: 0.12), value: model.hovered)
        .animation(.easeOut(duration: 0.18), value: model.slices)
    }

    private func sliceView(_ slice: RingSlice, index i: Int, geometry g: RingGeometry) -> some View {
        let isHovered = model.hovered == i && model.phase == .choosing
        let dimmed = model.phase != .choosing
        let shape = SliceShape(geometry: g, index: i)
        let labelRadius = (g.innerRadius + g.outerRadius - g.rim) / 2 + 2
        let labelPoint = RingGeometry.point(radius: labelRadius, angle: g.centerAngle(of: i))
        let anchor = UnitPoint(x: 0.5 + labelPoint.x / g.diameter, y: 0.5 + labelPoint.y / g.diameter)

        return ZStack {
            // Relleno + trazo grueso redondeado = esquinas redondeadas. El grupo evita que se sumen opacidades.
            ZStack {
                shape.fill(Color.white)
                shape.stroke(Color.white, style: StrokeStyle(lineWidth: 28, lineJoin: .round))
            }
            .compositingGroup()
            .opacity(dimmed ? 0.07 : (isHovered ? 0.36 : 0.17))

            VStack(spacing: 4) {
                if let symbol = slice.symbol {
                    Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                }
                Text(slice.label)
                    .font(.system(size: slice.symbol == nil ? 17 : 12, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize()
            }
            .foregroundStyle(Color.white.opacity(dimmed ? 0.35 : 1))
            .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            .offset(x: labelPoint.x, y: labelPoint.y)
        }
        .scaleEffect(isHovered ? 1.05 : 1, anchor: anchor)
    }

    private func center(_ g: RingGeometry) -> some View {
        let (text, color) = model.centerText
        return ZStack {
            Circle().fill(Color.black.opacity(0.6)).frame(width: g.innerRadius * 2, height: g.innerRadius * 2)
            Text(text)
                .font(.system(size: 15, weight: .heavy).monospacedDigit())
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(model.centerHovered && model.phase == .choosing ? 0.28 : 0.16)))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: g.innerRadius * 2 + 20)
        }
    }
}
