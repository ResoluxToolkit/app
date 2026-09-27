import SwiftUI

/// Luz de fundo atmosférica (portada do `AuroraBackground` do Mevolit).
///
/// Sem luz atrás do vidro não há refração: nenhum `GlassCard` faz sentido sem
/// isto por baixo. Os quatro orbes, opacidades, blur e o drift de 10 s são os
/// valores do tema que o operador aprovou — não reinterpretar sem ele pedir.
public struct AuroraBackground: View {
    @State private var drift = false

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Palette.background

                Circle()
                    .fill(Palette.deepViolet.opacity(0.48))
                    .frame(width: max(w * 0.9, 360), height: max(w * 0.9, 360))
                    .blur(radius: 85)
                    .offset(x: drift ? -w * 0.15 : -w * 0.25, y: -h * 0.25)

                Circle()
                    .fill(Palette.cyan.opacity(0.35))
                    .frame(width: max(w * 0.8, 320), height: max(w * 0.8, 320))
                    .blur(radius: 95)
                    .offset(x: drift ? w * 0.20 : w * 0.30, y: drift ? h * 0.05 : -h * 0.05)

                Circle()
                    .fill(Palette.magenta.opacity(0.24))
                    .frame(width: max(w * 0.7, 280), height: max(w * 0.7, 280))
                    .blur(radius: 80)
                    .offset(x: -w * 0.20, y: h * 0.20)

                Circle()
                    .fill(Palette.amber.opacity(0.18))
                    .frame(width: max(w * 0.75, 300), height: max(w * 0.75, 300))
                    .blur(radius: 90)
                    .offset(x: w * 0.10, y: h * 0.45)
            }
            .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: drift)
        }
        .ignoresSafeArea()
        .onAppear { drift = true }
    }
}
